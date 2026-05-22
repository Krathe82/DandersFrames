local addonName, DF = ...

if DF.RELEASE_CHANNEL == "release" then return end

local L = DF.L

-- ============================================================
-- COLOR CONSTANTS & SHARED HELPERS
-- Mirrors AuraDesigner's palette so the Text Designer reads as the same
-- visual family as the rest of the addon.
-- ============================================================

local C_BACKGROUND = {r = 0.08, g = 0.08, b = 0.08, a = 0.95}
local C_PANEL      = {r = 0.12, g = 0.12, b = 0.12, a = 1}
local C_ELEMENT    = {r = 0.18, g = 0.18, b = 0.18, a = 1}
local C_BORDER     = {r = 0.25, g = 0.25, b = 0.25, a = 1}
local C_HOVER      = {r = 0.22, g = 0.22, b = 0.22, a = 1}
local C_TEXT       = {r = 0.9, g = 0.9, b = 0.9, a = 1}
local C_TEXT_DIM   = {r = 0.6, g = 0.6, b = 0.6, a = 1}
local C_PANEL_DIM  = {r = 1, g = 1, b = 1, a = 0.03}
local C_BORDER_DIM = {r = 1, g = 1, b = 1, a = 0.08}

local function ApplyBackdrop(frame, bg, border)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    if bg then
        frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
    end
    if border then
        frame:SetBackdropBorderColor(border.r, border.g, border.b, border.a or 1)
    end
end

-- ============================================================
-- TEXT DESIGNER - GUI BUILDER
-- Phase 1: non-functional UI scaffold. Adds tab-level controls
-- (master toggle, Add Element button) and the empty state.
-- Card list, picker, and per-card editor land in subsequent tasks.
-- ============================================================

local CreateFrame = CreateFrame
local pairs, ipairs = pairs, ipairs

-- ============================================================
-- CONTENT TYPE CATALOG
-- 23 types organized into 6 categories. Each entry:
--   { key = "internal_id", label = L["Display Name"], category = "Health" }
-- The picker (search + pills + grouped list) reads this table.
-- Phase 2 will add per-type renderers; Phase 1 just stores `contentType` on
-- each element instance.
-- ============================================================

local CONTENT_CATEGORIES = {
    "identity", "health", "power", "shields", "status", "threat",
}

local CONTENT_CATEGORY_LABELS = {
    identity = L["Identity & Roster"],
    health   = L["Health"],
    power    = L["Power"],
    shields  = L["Shields & Heals"],
    status   = L["Status"],
    threat   = L["Threat & Range"],
}

local CONTENT_TYPES = {
    -- Identity & Roster
    { key = "name",              label = L["Name"],                       category = "identity" },
    { key = "class",             label = L["Class"],                      category = "identity" },
    { key = "group_number",      label = L["Group Number"],               category = "identity" },
    { key = "race_level_faction",label = L["Race / Level / Faction"],     category = "identity" },
    { key = "custom_static",     label = L["Custom Static Text"],         category = "identity" },
    -- Health
    { key = "hp_current",        label = L["Current HP"],                 category = "health"   },
    { key = "hp_max",            label = L["Max HP"],                     category = "health"   },
    { key = "hp_percent",        label = L["HP Percent"],                 category = "health"   },
    { key = "hp_deficit",        label = L["HP Deficit"],                 category = "health"   },
    { key = "hp_max_reduction",  label = L["Max HP Reduction %"],         category = "health"   },
    -- Power
    { key = "power_current",     label = L["Current Power"],              category = "power"    },
    { key = "power_percent",     label = L["Power %"],                    category = "power"    },
    { key = "power_deficit",     label = L["Power Deficit"],              category = "power"    },
    { key = "power_type_string", label = L["Power Type String"],          category = "power"    },
    -- Shields & Heals
    { key = "absorb_amount",     label = L["Absorb Amount"],              category = "shields"  },
    { key = "overshield_amount", label = L["Overshield Amount"],          category = "shields"  },
    { key = "heal_absorb_amount",label = L["Heal Absorb Amount"],         category = "shields"  },
    { key = "incoming_heal",     label = L["Incoming Heal"],              category = "shields"  },
    { key = "incoming_heal_mine",label = L["Incoming Heal From Me Only"], category = "shields"  },
    -- Status
    { key = "status_text",       label = L["Dead / Offline / Ghost"],     category = "status"   },
    -- Threat & Range
    { key = "aggro_flag",        label = L["Aggro Flag"],                 category = "threat"   },
    { key = "threat_percent",    label = L["Threat %"],                   category = "threat"   },
    { key = "range_text",        label = L["In-Range / OOR Text"],        category = "threat"   },
}

local function FindContentType(key)
    for _, t in ipairs(CONTENT_TYPES) do
        if t.key == key then return t end
    end
end

-- ============================================================
-- CONFIRMATION POPUP for element delete
-- ============================================================
StaticPopupDialogs["DF_TEXTDESIGNER_DELETE_ELEMENT"] = {
    text = L["Delete this text element?"],
    button1 = L["Yes"],
    button2 = L["No"],
    OnAccept = function(self, data)
        if data and data.onConfirm then data.onConfirm() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================
-- BODY SECTION HELPERS
-- Shared layout primitives used by the Content / Appearance / Position
-- section builders.
-- ============================================================

local SECTION_LABEL_HEIGHT = 18
local FIELD_ROW_HEIGHT = 28
local SECTION_GAP = 8

local function CreateSectionLabel(GUI, parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(fs, 9, "OUTLINE")
    fs:SetText(text:upper())
    fs:SetTextColor(0.5, 0.7, 1, 0.9)
    return fs
end

-- Returns the y-offset where the next section should start (negative, goes down).
local function BuildContentSection(GUI, parent, elem, yStart)
    local label = CreateSectionLabel(GUI, parent, L["Content"])
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yStart)
    local y = yStart - SECTION_LABEL_HEIGHT

    local ct = FindContentType(elem.contentType)
    if not ct then return y end

    -- Numeric types: abbreviate checkbox
    if ct.key == "hp_current" or ct.key == "hp_max" or ct.key == "hp_deficit"
       or ct.key == "power_current" or ct.key == "power_deficit"
       or ct.key == "absorb_amount" or ct.key == "overshield_amount"
       or ct.key == "heal_absorb_amount"
       or ct.key == "incoming_heal" or ct.key == "incoming_heal_mine"
    then
        elem.abbreviate = elem.abbreviate
        if elem.abbreviate == nil then elem.abbreviate = true end
        local abbrev = GUI:CreateCheckbox(parent, L["Abbreviate"], elem, "abbreviate", function() end)
        abbrev:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        y = y - FIELD_ROW_HEIGHT

    -- Percent types: decimals slider
    elseif ct.key == "hp_percent" or ct.key == "power_percent"
           or ct.key == "hp_max_reduction" or ct.key == "threat_percent" then
        elem.decimals = elem.decimals or 0
        local dec = GUI:CreateSlider(parent, L["Decimal Places"], 0, 2, 1, elem, "decimals", function() end)
        dec:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        y = y - FIELD_ROW_HEIGHT

    -- Name: length cap + truncate mode
    elseif ct.key == "name" then
        elem.nameLength = elem.nameLength or 12
        local lenSlider = GUI:CreateSlider(parent, L["Length"], 1, 30, 1, elem, "nameLength", function() end)
        lenSlider:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        y = y - FIELD_ROW_HEIGHT

        elem.truncateMode = elem.truncateMode or "ELLIPSIS"
        local truncOpts = { ELLIPSIS = L["Ellipsis"], CUT = L["Cut"] }
        local truncDrop = GUI:CreateDropdown(parent, L["Truncate Mode"], truncOpts, elem, "truncateMode", function() end)
        truncDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        y = y - FIELD_ROW_HEIGHT

    -- Custom static text: a plain edit box
    elseif ct.key == "custom_static" then
        elem.staticText = elem.staticText or ""
        local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        edit:SetSize(240, 20)
        edit:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y - 2)
        edit:SetAutoFocus(false)
        edit:SetText(elem.staticText)
        edit:SetScript("OnTextChanged", function(self)
            elem.staticText = self:GetText()
        end)
        edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local lbl = parent:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(lbl, 10, "")
        lbl:SetText(L["Text"])
        lbl:SetPoint("RIGHT", edit, "LEFT", -8, 0)
        y = y - FIELD_ROW_HEIGHT

    -- Group number: prefix/suffix format
    elseif ct.key == "group_number" then
        elem.groupFormat = elem.groupFormat or "SUFFIX"
        local opts = {
            PREFIX = L["Prefix"],
            SUFFIX = L["Suffix"],
            STANDALONE = L["Standalone"],
        }
        local fmtDrop = GUI:CreateDropdown(parent, L["Format"], opts, elem, "groupFormat", function() end)
        fmtDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        y = y - FIELD_ROW_HEIGHT
    end
    -- Types with no Content-section fields fall through:
    -- class, status_text, aggro_flag, range_text, power_type_string, race_level_faction.
    -- They render only the section header (no fields), which is fine.

    return y - SECTION_GAP
end

-- ============================================================
-- 9-POINT ANCHOR GRID WIDGET
-- 3x3 grid of buttons mapping to TOPLEFT, TOP, TOPRIGHT, LEFT, CENTER, etc.
-- Click selects. Selected button is highlighted.
-- ============================================================

local ANCHOR_GRID = {
    {"TOPLEFT",    "TOP",      "TOPRIGHT"},
    {"LEFT",       "CENTER",   "RIGHT"},
    {"BOTTOMLEFT", "BOTTOM",   "BOTTOMRIGHT"},
}

local function CreateAnchorGrid(GUI, parent, elem)
    local grid = CreateFrame("Frame", nil, parent)
    grid:SetSize(60, 60)

    local btns = {}
    local function ApplyButtonState(b, active)
        if active then
            b:SetBackdropColor(0.3, 0.55, 0.9, 0.9)
            b:SetBackdropBorderColor(0.5, 0.75, 1, 1)
        else
            b:SetBackdropColor(0.12, 0.14, 0.18, 0.8)
            b:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.6)
        end
    end

    for row = 1, 3 do
        for col = 1, 3 do
            local point = ANCHOR_GRID[row][col]
            local b = CreateFrame("Button", nil, grid, "BackdropTemplate")
            b:SetSize(18, 18)
            b:SetPoint("TOPLEFT", grid, "TOPLEFT", (col - 1) * 20, -((row - 1) * 20))
            b:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            b.point = point
            btns[point] = b
            b:SetScript("OnClick", function()
                elem.anchor = point
                for p, bb in pairs(btns) do
                    ApplyButtonState(bb, p == point)
                end
            end)
        end
    end

    -- Initial state
    elem.anchor = elem.anchor or "CENTER"
    for p, b in pairs(btns) do
        ApplyButtonState(b, p == elem.anchor)
    end

    return grid
end

-- Returns the y-offset where the next section should start (negative, goes down).
local function BuildAppearanceSection(GUI, parent, elem, yStart)
    local label = CreateSectionLabel(GUI, parent, L["Appearance"])
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yStart)
    local y = yStart - SECTION_LABEL_HEIGHT

    -- Defaults
    elem.font = elem.font or "DF Roboto SemiBold"
    elem.fontSize = elem.fontSize or 10
    elem.outline = elem.outline or "SHADOW"
    elem.color = elem.color or {r = 1, g = 1, b = 1, a = 1}
    if elem.useClassColor == nil then elem.useClassColor = false end

    -- Font (LSM-aware dropdown). Use GUI:CreateFontDropdown if available;
    -- otherwise fall back to a generic dropdown listing the current font only.
    local fontDrop
    if GUI.CreateFontDropdown then
        fontDrop = GUI:CreateFontDropdown(parent, L["Font"], elem, "font", function() end)
    else
        fontDrop = GUI:CreateDropdown(parent, L["Font"], {[elem.font] = elem.font}, elem, "font", function() end)
    end
    fontDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    -- Size
    local sizeSlider = GUI:CreateSlider(parent, L["Size"], 6, 40, 1, elem, "fontSize", function() end)
    sizeSlider:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    -- Outline
    local outlineOpts = {
        NONE = L["None"],
        OUTLINE = L["Outline"],
        THICKOUTLINE = L["Thick Outline"],
        SHADOW = L["Shadow"],
    }
    local outlineDrop = GUI:CreateDropdown(parent, L["Outline"], outlineOpts, elem, "outline", function() end)
    outlineDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    -- Color picker + Use Class Color toggle.
    -- CreateColorPicker signature: (parent, label, dbTable, dbKey, hasAlpha, callback, ...)
    local colorPicker = GUI:CreateColorPicker(parent, L["Color"], elem, "color", true, function() end)
    colorPicker:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)

    local classColorCheck = GUI:CreateCheckbox(parent, L["Use Class Color"], elem, "useClassColor", function()
        if elem.useClassColor then
            if colorPicker.Disable then colorPicker:Disable() end
            colorPicker:SetAlpha(0.4)
        else
            if colorPicker.Enable then colorPicker:Enable() end
            colorPicker:SetAlpha(1)
        end
    end)
    classColorCheck:SetPoint("LEFT", colorPicker, "RIGHT", 16, 0)

    -- Apply initial grayed state if class color is on
    if elem.useClassColor then
        if colorPicker.Disable then colorPicker:Disable() end
        colorPicker:SetAlpha(0.4)
    end
    y = y - FIELD_ROW_HEIGHT

    return y - SECTION_GAP
end

-- Returns the y-offset where the next section should start (negative, goes down).
local function BuildPositionSection(GUI, parent, elem, yStart)
    local label = CreateSectionLabel(GUI, parent, L["Position"])
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yStart)
    local y = yStart - SECTION_LABEL_HEIGHT

    -- Defaults
    elem.anchor = elem.anchor or "CENTER"
    elem.offsetX = elem.offsetX or 0
    elem.offsetY = elem.offsetY or 0
    elem.frameLevel = elem.frameLevel or 25
    elem.frameStrata = elem.frameStrata or "INHERIT"

    -- Anchor grid on the left
    local grid = CreateAnchorGrid(GUI, parent, elem)
    grid:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y - 4)
    local gridLabel = parent:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(gridLabel, 8, "")
    gridLabel:SetText(L["Anchor"])
    gridLabel:SetPoint("TOP", grid, "BOTTOM", 0, -2)
    gridLabel:SetTextColor(0.6, 0.6, 0.6)

    -- Offsets / frame settings on the right
    local rightX = 100
    local xSlider = GUI:CreateSlider(parent, L["Offset X"], -200, 200, 1, elem, "offsetX", function() end)
    xSlider:SetPoint("TOPLEFT", parent, "TOPLEFT", rightX, y)
    y = y - FIELD_ROW_HEIGHT

    local ySlider = GUI:CreateSlider(parent, L["Offset Y"], -200, 200, 1, elem, "offsetY", function() end)
    ySlider:SetPoint("TOPLEFT", parent, "TOPLEFT", rightX, y)
    y = y - FIELD_ROW_HEIGHT

    local lvlSlider = GUI:CreateSlider(parent, L["Frame Level"], 1, 200, 1, elem, "frameLevel", function() end)
    lvlSlider:SetPoint("TOPLEFT", parent, "TOPLEFT", rightX, y)
    y = y - FIELD_ROW_HEIGHT

    local strataOpts = {
        INHERIT = L["Inherit"],
        LOW = "LOW",
        MEDIUM = "MEDIUM",
        HIGH = "HIGH",
        DIALOG = "DIALOG",
    }
    local strataDrop = GUI:CreateDropdown(parent, L["Frame Strata"], strataOpts, elem, "frameStrata", function() end)
    strataDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", rightX, y)
    y = y - FIELD_ROW_HEIGHT

    return y - SECTION_GAP
end

-- ============================================================
-- ADD ELEMENT PICKER
-- A floating dropdown: search input, category pill row, grouped list.
-- Calls onPick(typeKey) when the user selects a type. Closes on pick.
-- Click the Add Element button again to dismiss without picking.
-- ============================================================

local function BuildPicker(GUI, parent, tdDB, onPick)
    local drop = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    drop:SetFrameStrata("FULLSCREEN_DIALOG")
    drop:SetClampedToScreen(true)
    drop:SetSize(280, 380)
    ApplyBackdrop(drop, C_BACKGROUND, C_BORDER)
    drop:Hide()

    -- ── Search input ─────────────────────────────────────────
    local searchBox = CreateFrame("EditBox", nil, drop, "InputBoxTemplate")
    searchBox:SetSize(240, 20)
    searchBox:SetPoint("TOPLEFT", drop, "TOPLEFT", 16, -10)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("ChatFontNormal")
    drop.searchBox = searchBox

    -- ── Pill row (category filters) ─────────────────────────
    -- Sized to the dropdown width minus side padding so flow-layout can wrap.
    local PILL_ROW_PAD = 16
    local pillRow = CreateFrame("Frame", nil, drop)
    pillRow:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -6)
    pillRow:SetPoint("TOPRIGHT", drop, "TOPRIGHT", -PILL_ROW_PAD, 0)
    pillRow:SetHeight(18)
    local pills = {}

    local CHIP_H, CHIP_GAP, CHIP_ROW_GAP = 18, 4, 4

    local function MakePill(label, key)
        local p = CreateFrame("Button", nil, pillRow, "BackdropTemplate")
        p:SetHeight(CHIP_H)
        ApplyBackdrop(p, C_PANEL, C_BORDER)
        local fs = p:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(fs, 9, "")
        fs:SetPoint("CENTER")
        fs:SetText(label)
        p:SetWidth(fs:GetStringWidth() + 14)
        p.key = key
        p.fs = fs
        return p
    end

    pills[#pills+1] = MakePill(L["All"], "_all")
    for _, cat in ipairs(CONTENT_CATEGORIES) do
        pills[#pills+1] = MakePill(CONTENT_CATEGORY_LABELS[cat], cat)
    end

    -- Flow-layout: position pills with wrapping on parent resize
    local function LayoutPills()
        local maxW = pillRow:GetWidth()
        if maxW <= 0 then maxW = 260 end
        local cx, cy = 0, 0
        for _, btn in ipairs(pills) do
            local bw = btn:GetWidth()
            if cx > 0 and (cx + bw) > maxW then
                cx = 0
                cy = cy - (CHIP_H + CHIP_ROW_GAP)
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", pillRow, "TOPLEFT", cx, cy)
            cx = cx + bw + CHIP_GAP
        end
        pillRow:SetHeight(math.max(-cy + CHIP_H, CHIP_H))
    end
    LayoutPills()
    pillRow:SetScript("OnSizeChanged", LayoutPills)

    local activePill = "_all"
    local function ApplyPillState()
        for _, p in ipairs(pills) do
            if p.key == activePill then
                p:SetBackdropColor(0.2, 0.4, 0.7, 1)
                p:SetBackdropBorderColor(0.4, 0.7, 1, 1)
                p.fs:SetTextColor(1, 1, 1)
            else
                p:SetBackdropColor(C_PANEL.r, C_PANEL.g, C_PANEL.b, C_PANEL.a)
                p:SetBackdropBorderColor(C_BORDER.r, C_BORDER.g, C_BORDER.b, C_BORDER.a)
                p.fs:SetTextColor(C_TEXT.r, C_TEXT.g, C_TEXT.b)
            end
        end
    end
    ApplyPillState()

    -- ── Scrolling list of items ─────────────────────────────
    -- Anchor to bottom of pillRow so wrapped pills push the list down correctly.
    local scrollFrame = CreateFrame("ScrollFrame", nil, drop, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", pillRow, "BOTTOMLEFT", 4, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", drop, "BOTTOMRIGHT", -20, 10)
    DF.GUI.StyleScrollBar(scrollFrame)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(current - delta * 20, self:GetVerticalScrollRange())))
    end)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(244, 1)
    scrollFrame:SetScrollChild(scrollChild)
    drop.scrollChild = scrollChild

    local itemPool = {}
    local function AcquireItem()
        for _, it in ipairs(itemPool) do
            if not it:IsShown() then return it end
        end
        local it = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
        it:SetSize(240, 16)
        it:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
        it:SetBackdropColor(0.2, 0.4, 0.7, 0)
        local fs = it:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(fs, 10, "")
        fs:SetPoint("LEFT", it, "LEFT", 14, 0)
        it.fs = fs
        it:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.4, 0.7, 0.3)
        end)
        it:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.2, 0.4, 0.7, 0)
        end)
        itemPool[#itemPool+1] = it
        return it
    end

    local headerPool = {}
    local function AcquireHeader()
        for _, h in ipairs(headerPool) do
            if not h:IsShown() then return h end
        end
        local h = scrollChild:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(h, 9, "")
        h:SetJustifyH("LEFT")
        headerPool[#headerPool+1] = h
        return h
    end

    local function HideAll()
        for _, it in ipairs(itemPool) do it:Hide() end
        for _, h in ipairs(headerPool) do h:Hide() end
    end

    local function RenderList()
        HideAll()
        local query = (searchBox:GetText() or ""):lower()
        query = query:match("^%s*(.-)%s*$") or ""

        local y = -2
        for _, cat in ipairs(CONTENT_CATEGORIES) do
            if activePill == "_all" or activePill == cat then
                local matches = {}
                for _, t in ipairs(CONTENT_TYPES) do
                    if t.category == cat then
                        if query == "" or t.label:lower():find(query, 1, true) then
                            matches[#matches+1] = t
                        end
                    end
                end
                if #matches > 0 then
                    local h = AcquireHeader()
                    h:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, y)
                    h:SetText(CONTENT_CATEGORY_LABELS[cat]:upper())
                    h:SetTextColor(0.5, 0.7, 1, 0.9)
                    h:Show()
                    y = y - 14
                    for _, t in ipairs(matches) do
                        local it = AcquireItem()
                        it:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, y)
                        it.fs:SetText(t.label)
                        it.fs:SetTextColor(0.95, 0.95, 0.95)
                        it:SetScript("OnClick", function()
                            drop:Hide()
                            if onPick then onPick(t.key) end
                        end)
                        it:Show()
                        y = y - 16
                    end
                    y = y - 4
                end
            end
        end
        scrollChild:SetHeight(math.max(1, -y + 4))
    end

    searchBox:SetScript("OnTextChanged", RenderList)

    for _, p in ipairs(pills) do
        p:SetScript("OnClick", function(self)
            activePill = self.key
            ApplyPillState()
            RenderList()
        end)
    end

    function drop:Open(anchor)
        searchBox:SetText("")
        activePill = "_all"
        ApplyPillState()
        RenderList()
        drop:ClearAllPoints()
        drop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        drop:Show()
        searchBox:SetFocus()
    end

    drop:SetScript("OnHide", function() searchBox:ClearFocus() end)

    return drop
end

-- ============================================================
-- ELEMENT CARD
-- A collapsible card showing one text element. Click header to expand.
-- Body sections (Content / Appearance / Position) added in Tasks 7-9;
-- header action icons added in Task 6.
-- ============================================================

local CARD_HEADER_HEIGHT = 28
local CARD_BODY_HEIGHT_PLACEHOLDER = 80  -- Tasks 7-9 set real height

local function BuildCard(GUI, parent, elem, tdDB, state, page)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(1, CARD_HEADER_HEIGHT)  -- width set by anchor
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0.08, 0.10, 0.13, 0.7)
    card:SetBackdropBorderColor(0.2, 0.25, 0.3, 0.8)

    -- Context for callbacks (delete needs to remove from db and re-render)
    card._tdDB = tdDB
    card._state = state
    card._GUI = GUI
    card._page = page

    -- ── HEADER (always visible) ──────────────────────────────
    local header = CreateFrame("Button", nil, card)
    header:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    header:SetHeight(CARD_HEADER_HEIGHT)
    card.header = header

    local title = header:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(title, 11, "OUTLINE")
    title:SetPoint("LEFT", header, "LEFT", 10, 0)
    local ct = FindContentType(elem.contentType)
    title:SetText(ct and ct.label or elem.contentType)
    title:SetTextColor(0.95, 0.95, 0.95)
    card.title = title

    local meta = header:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(meta, 9, "")
    meta:SetPoint("LEFT", title, "RIGHT", 8, 0)
    meta:SetText("")  -- Tasks 7-9 will populate with position/format summary
    meta:SetTextColor(0.55, 0.6, 0.7)
    card.meta = meta

    -- ── ACTION ICONS (right side of header) ──────────────────
    local ICON_SIZE = 18
    local ICON_GAP = 4

    -- Delete (rightmost)
    local deleteBtn = CreateFrame("Button", nil, header)
    deleteBtn:SetSize(ICON_SIZE, ICON_SIZE)
    deleteBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    local deleteFs = deleteBtn:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(deleteFs, 12, "OUTLINE")
    deleteFs:SetPoint("CENTER")
    deleteFs:SetText("X")
    deleteFs:SetTextColor(0.9, 0.3, 0.3)
    card.deleteBtn = deleteBtn

    -- Drag handle (Task 10 wires up actual drag)
    local dragBtn = CreateFrame("Button", nil, header)
    dragBtn:SetSize(ICON_SIZE, ICON_SIZE)
    dragBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -ICON_GAP, 0)
    local dragFs = dragBtn:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(dragFs, 12, "OUTLINE")
    dragFs:SetPoint("CENTER")
    dragFs:SetText("=")  -- placeholder glyph
    dragFs:SetTextColor(0.7, 0.7, 0.7)
    card.dragBtn = dragBtn

    -- Visibility toggle (eye)
    local eyeBtn = CreateFrame("Button", nil, header)
    eyeBtn:SetSize(ICON_SIZE, ICON_SIZE)
    eyeBtn:SetPoint("RIGHT", dragBtn, "LEFT", -ICON_GAP, 0)
    local eyeFs = eyeBtn:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(eyeFs, 12, "OUTLINE")
    eyeFs:SetPoint("CENTER")
    eyeFs:SetText(elem.enabled and "O" or "-")
    local function updateEyeColor()
        local c = elem.enabled and 0.95 or 0.45
        eyeFs:SetTextColor(c, c, c)
    end
    updateEyeColor()
    card.eyeBtn = eyeBtn
    card.eyeFs = eyeFs

    -- Stop header click-through when clicking icons
    for _, btn in ipairs({eyeBtn, dragBtn, deleteBtn}) do
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetFrameLevel(header:GetFrameLevel() + 1)
    end

    -- Drag-to-reorder (Task 10): drag the handle to move the card up/down
    dragBtn:RegisterForDrag("LeftButton")
    dragBtn:SetScript("OnDragStart", function()
        card._dragging = true
        card:SetFrameStrata("HIGH")
        card:SetAlpha(0.7)
        DF:Debug("TD", "Drag start id=%d", elem.id)
    end)
    dragBtn:SetScript("OnDragStop", function()
        if not card._dragging then return end
        card._dragging = false
        card:SetFrameStrata("MEDIUM")
        card:SetAlpha(1)

        local capturedTdDB = card._tdDB
        local capturedState = card._state
        local capturedGUI = card._GUI
        local capturedPage = card._page
        if not capturedTdDB or not capturedState then return end

        -- Find which position the card should move to based on cursor Y
        local _, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cursorY = cursorY / scale

        local newIndex = #capturedTdDB.elements
        for i, e in ipairs(capturedTdDB.elements) do
            local target = capturedState.cardFrames[e.id]
            if target and target ~= card and target:IsShown() then
                local top = target:GetTop()
                if top and cursorY > top then
                    newIndex = i
                    break
                end
            end
        end

        -- Find current index
        local currentIndex
        for i, e in ipairs(capturedTdDB.elements) do
            if e.id == elem.id then currentIndex = i; break end
        end

        if currentIndex and currentIndex ~= newIndex then
            local moved = table.remove(capturedTdDB.elements, currentIndex)
            table.insert(capturedTdDB.elements, math.min(newIndex, #capturedTdDB.elements + 1), moved)
            DF:Debug("TD", "Reorder id=%d from %d to %d", elem.id, currentIndex, newIndex)
        end

        if DF.TextDesigner.RenderCardList then
            DF.TextDesigner.RenderCardList(capturedGUI, capturedPage, capturedTdDB, capturedState)
        end
    end)

    -- Visibility toggle behaviour
    eyeBtn:SetScript("OnClick", function()
        elem.enabled = not elem.enabled
        eyeFs:SetText(elem.enabled and "O" or "-")
        updateEyeColor()
        DF:Debug("TD", "Element %d enabled=%s", elem.id, tostring(elem.enabled))
    end)

    -- Delete behaviour
    deleteBtn:SetScript("OnClick", function()
        local popup = StaticPopup_Show("DF_TEXTDESIGNER_DELETE_ELEMENT")
        if popup then
            popup.data = {
                onConfirm = function()
                    local capturedTdDB = card._tdDB
                    local capturedState = card._state
                    local capturedGUI = card._GUI
                    local capturedPage = card._page
                    if not capturedTdDB or not capturedState then return end
                    for i, e in ipairs(capturedTdDB.elements) do
                        if e.id == elem.id then
                            table.remove(capturedTdDB.elements, i)
                            break
                        end
                    end
                    capturedState.cardFrames[elem.id] = nil
                    card:Hide()
                    card:SetParent(nil)
                    if DF.TextDesigner.RenderCardList then
                        DF.TextDesigner.RenderCardList(capturedGUI, capturedPage, capturedTdDB, capturedState)
                    end
                    DF:Debug("TD", "Deleted element id=%d (remaining=%d)",
                        elem.id, #capturedTdDB.elements)
                end,
            }
        end
    end)

    -- ── BODY (hidden by default) ─────────────────────────────
    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    body:SetHeight(CARD_BODY_HEIGHT_PLACEHOLDER)
    body:Hide()
    card.body = body

    -- ── BODY CONTENT ─────────────────────────────────────────
    local yEnd = BuildContentSection(GUI, body, elem, -10)
    yEnd = BuildAppearanceSection(GUI, body, elem, yEnd)
    yEnd = BuildPositionSection(GUI, body, elem, yEnd)
    body:SetHeight(-yEnd + 10)

    -- Update the header meta line with current anchor + offset summary
    function card:UpdateMeta()
        meta:SetText((elem.anchor or "CENTER") .. " · " .. (elem.offsetX or 0) .. "," .. (elem.offsetY or 0))
    end
    card:UpdateMeta()

    -- ── EXPAND / COLLAPSE ────────────────────────────────────
    card.expanded = false
    function card:Expand()
        self.expanded = true
        self.body:Show()
        self:SetHeight(CARD_HEADER_HEIGHT + self.body:GetHeight())
    end
    function card:Collapse()
        self.expanded = false
        self.body:Hide()
        self:SetHeight(CARD_HEADER_HEIGHT)
    end
    header:SetScript("OnClick", function()
        if card.expanded then card:Collapse() else card:Expand() end
    end)

    return card
end

-- ============================================================
-- CARD LIST RENDERER
-- Iterates db.elements in order, builds/positions cards. Uses a pool
-- to avoid creating/destroying card frames on every render.
-- ============================================================

local function RenderCardList(GUI, page, tdDB, state)
    -- Hide all existing card frames first
    for _, card in pairs(state.cardFrames) do
        card:Hide()
    end

    if #tdDB.elements == 0 then
        if state.emptyMsg then state.emptyMsg:Show() end
        state.listChild:SetHeight(1)
        return
    end

    if state.emptyMsg then state.emptyMsg:Hide() end

    local y = 0
    local CARD_GAP = 4
    for _, elem in ipairs(tdDB.elements) do
        local card = state.cardFrames[elem.id]
        if not card then
            card = BuildCard(GUI, state.listChild, elem, tdDB, state, page)
            state.cardFrames[elem.id] = card
        end
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", state.listChild, "TOPLEFT", 2, y)
        card:SetPoint("TOPRIGHT", state.listChild, "TOPRIGHT", -2, y)
        card:Show()
        if card.expanded then
            y = y - (CARD_HEADER_HEIGHT + card.body:GetHeight()) - CARD_GAP
        else
            y = y - CARD_HEADER_HEIGHT - CARD_GAP
        end
    end
    state.listChild:SetHeight(math.max(1, -y + 4))
end

DF.TextDesigner.RenderCardList = RenderCardList  -- exposed for Task 6+

-- The page state across builder invocations. Cached on the page frame.
local function GetState(page)
    page.dfTD = page.dfTD or {
        cardFrames = {},     -- pool of card frames keyed by elementID
        pickerFrame = nil,   -- the Add Element dropdown (created lazily)
    }
    return page.dfTD
end

-- ============================================================
-- BUILD ENTRYPOINT
-- ============================================================

function DF.BuildTextDesignerPage(GUI, page, db)
    DF.TextDesigner:EnsureDB(db)
    local tdDB = db.textDesigner
    local state = GetState(page)

    if state.built then return end
    state.built = true

    -- ── TAB-LEVEL CONTROLS BAR ───────────────────────────────
    -- Master enable toggle + Add Element button, side by side at top.
    local controlsBar = CreateFrame("Frame", nil, page.child)
    controlsBar:SetHeight(32)
    controlsBar:SetPoint("TOPLEFT", page.child, "TOPLEFT", 10, -10)
    controlsBar:SetPoint("TOPRIGHT", page.child, "TOPRIGHT", -10, -10)

    -- Master toggle
    local enableCheck = GUI:CreateCheckbox(
        controlsBar,
        L["Enable Text Designer"],
        tdDB,
        "enabled",
        function() DF:Debug("TD", "Enable Text Designer = %s", tostring(tdDB.enabled)) end
    )
    enableCheck:SetPoint("LEFT", controlsBar, "LEFT", 0, 0)

    -- Add Element button — opens the picker dropdown.
    local addBtn
    addBtn = GUI:CreateButton(controlsBar, "+ " .. L["Add Text Element"], 160, 22, function()
        if not state.pickerFrame then
            state.pickerFrame = BuildPicker(GUI, page, tdDB, function(typeKey)
                -- Create a new element instance
                local id = tdDB.nextElementID
                tdDB.nextElementID = id + 1
                local elem = {
                    id = id,
                    contentType = typeKey,
                    enabled = true,
                }
                table.insert(tdDB.elements, elem)
                DF:Debug("TD", "Added element id=%d type=%s (total=%d)",
                    id, typeKey, #tdDB.elements)
                -- Hide empty state if it's still visible
                if state.emptyMsg then state.emptyMsg:Hide() end
                RenderCardList(GUI, page, tdDB, state)
            end)
        end
        if state.pickerFrame:IsShown() then
            state.pickerFrame:Hide()
        else
            state.pickerFrame:Open(addBtn)
        end
    end)
    addBtn:SetPoint("RIGHT", controlsBar, "RIGHT", 0, 0)
    state.addBtn = addBtn

    -- ── CARD LIST AREA ───────────────────────────────────────
    -- A bordered panel hosts the section header and the scrollable card list.
    -- Empty-state message centers inside the panel when no elements exist.
    local listPanel = CreateFrame("Frame", nil, page.child, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", controlsBar, "BOTTOMLEFT", 0, -10)
    listPanel:SetPoint("BOTTOMRIGHT", page.child, "BOTTOMRIGHT", -10, 10)
    ApplyBackdrop(listPanel, C_PANEL_DIM, C_BORDER_DIM)

    local listContainer = CreateFrame("ScrollFrame", nil, listPanel, "ScrollFrameTemplate")
    listContainer:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 6, -6)
    listContainer:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -22, 8)
    DF.GUI.StyleScrollBar(listContainer)
    listContainer:EnableMouseWheel(true)
    listContainer:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(current - delta * 20, self:GetVerticalScrollRange())))
    end)

    local listChild = CreateFrame("Frame", nil, listContainer)
    listChild:SetSize(1, 1)
    listContainer:SetScrollChild(listChild)
    state.listPanel = listPanel
    state.listContainer = listContainer
    state.listChild = listChild

    local emptyMsg = listPanel:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(emptyMsg, 11, "")
    emptyMsg:SetPoint("CENTER", listContainer, "CENTER", 0, 0)
    emptyMsg:SetText(L["No text elements yet. Click '+ Add Text Element' to create one."])
    emptyMsg:SetTextColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, 1)
    state.emptyMsg = emptyMsg

    -- Initial render — populate any existing elements
    RenderCardList(GUI, page, tdDB, state)
end
