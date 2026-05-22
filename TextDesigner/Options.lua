local addonName, DF = ...

if DF.RELEASE_CHANNEL == "release" then return end

local L = DF.L

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
-- ADD ELEMENT PICKER
-- A floating dropdown: search input, category pill row, grouped list.
-- Calls onPick(typeKey) when the user selects a type. Closes on pick or
-- when the user clicks outside.
-- ============================================================

local function BuildPicker(GUI, parent, tdDB, onPick)
    local drop = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    drop:SetFrameStrata("DIALOG")
    drop:SetSize(280, 380)
    drop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    drop:SetBackdropColor(0.05, 0.07, 0.1, 0.98)
    drop:SetBackdropBorderColor(0.3, 0.5, 0.8, 0.6)
    drop:Hide()

    -- ── Search input ─────────────────────────────────────────
    local searchBox = CreateFrame("EditBox", nil, drop, "InputBoxTemplate")
    searchBox:SetSize(240, 20)
    searchBox:SetPoint("TOPLEFT", drop, "TOPLEFT", 16, -10)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("ChatFontNormal")
    drop.searchBox = searchBox

    -- ── Pill row (category filters) ─────────────────────────
    local pillRow = CreateFrame("Frame", nil, drop)
    pillRow:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -6)
    pillRow:SetSize(260, 22)
    local pills = {}

    local function MakePill(label, key, x)
        local p = CreateFrame("Button", nil, pillRow, "BackdropTemplate")
        p:SetSize(0, 18)
        p:SetPoint("LEFT", pillRow, "LEFT", x, 0)
        p:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        p:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
        p:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.6)
        local fs = p:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(fs, 9, "")
        fs:SetPoint("CENTER")
        fs:SetText(label)
        local w = fs:GetStringWidth() + 14
        p:SetWidth(w)
        p.key = key
        p.fs = fs
        return p, w
    end

    local pillX = 0
    local allPill, w = MakePill(L["All"], "_all", pillX)
    pills[#pills+1] = allPill
    pillX = pillX + w + 4
    for _, cat in ipairs(CONTENT_CATEGORIES) do
        local pp, ww = MakePill(CONTENT_CATEGORY_LABELS[cat], cat, pillX)
        pills[#pills+1] = pp
        pillX = pillX + ww + 4
    end

    local activePill = "_all"
    local function ApplyPillState()
        for _, p in ipairs(pills) do
            if p.key == activePill then
                p:SetBackdropColor(0.2, 0.4, 0.7, 1)
                p:SetBackdropBorderColor(0.4, 0.7, 1, 1)
                p.fs:SetTextColor(1, 1, 1)
            else
                p:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
                p:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.6)
                p.fs:SetTextColor(0.75, 0.75, 0.75)
            end
        end
    end
    ApplyPillState()

    -- ── Scrolling list of items ─────────────────────────────
    local scrollFrame = CreateFrame("ScrollFrame", nil, drop, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", pillRow, "BOTTOMLEFT", 4, -6)
    scrollFrame:SetSize(244, 290)

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
        local fs = it:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(fs, 10, "")
        fs:SetPoint("LEFT", it, "LEFT", 14, 0)
        it.fs = fs
        it:SetScript("OnEnter", function(self)
            self:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
            self:SetBackdropColor(0.2, 0.4, 0.7, 0.3)
        end)
        it:SetScript("OnLeave", function(self)
            self:SetBackdrop(nil)
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
        local query = searchBox:GetText() or ""
        query = query:lower():gsub("%s+", "")

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
    local addBtn = GUI:CreateButton(controlsBar, "+ " .. L["Add Text Element"], 160, 22, function()
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
                -- Card rendering lands in Task 5; for now just confirm via /dump
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

    -- ── EMPTY STATE / CARD LIST CONTAINER ────────────────────
    -- Centered message when no elements exist; replaced by the card list
    -- (Task 5) once elements are added.
    local listContainer = CreateFrame("Frame", nil, page.child)
    listContainer:SetPoint("TOPLEFT", controlsBar, "BOTTOMLEFT", 0, -10)
    listContainer:SetPoint("BOTTOMRIGHT", page.child, "BOTTOMRIGHT", -10, 10)
    state.listContainer = listContainer

    local emptyMsg = listContainer:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(emptyMsg, 11, "")
    emptyMsg:SetPoint("CENTER", listContainer, "CENTER", 0, 0)
    emptyMsg:SetText(L["No text elements yet. Click '+ Add Text Element' to create one."])
    emptyMsg:SetTextColor(0.6, 0.6, 0.6, 1)
    state.emptyMsg = emptyMsg

    -- Hide empty state if there are already elements (preserves user state across rebuilds)
    if #tdDB.elements > 0 then emptyMsg:Hide() end
end
