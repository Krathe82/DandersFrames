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
-- Card body backdrop — distinctly darker than C_ELEMENT (the header colour)
-- so the body content visually separates from the header. Mirrors AD's
-- two-layer card chrome (AuraDesigner/Options.lua:4463-4468).
local C_BODY_BG    = {r = 0.09, g = 0.09, b = 0.09, a = 1}
local C_BORDER     = {r = 0.25, g = 0.25, b = 0.25, a = 1}
local C_HOVER      = {r = 0.22, g = 0.22, b = 0.22, a = 1}
local C_TEXT       = {r = 0.9, g = 0.9, b = 0.9, a = 1}
local C_TEXT_DIM   = {r = 0.6, g = 0.6, b = 0.6, a = 1}
-- Recessed dark backdrop for the list panel — distinctly darker than C_ELEMENT
-- (the card color) so cards visibly sit "on top" of the panel surface.
local C_LIST_PANEL     = {r = 0.04, g = 0.04, b = 0.04, a = 1}

-- Destructive action red — matches Aura Designer's delete X cross palette.
local C_DESTRUCTIVE       = {r = 0.55, g = 0.20, b = 0.20, a = 1}
local C_DESTRUCTIVE_HOVER = {r = 1.00, g = 0.35, b = 0.35, a = 1}

-- Primary-CTA backdrop multipliers (applied to the theme accent color).
-- Mirrors AuraDesigner/Options.lua:4894-4915 "+ Add Indicator" button.
local CTA_BG_RESTING     = 0.10
local CTA_BORDER_RESTING = 0.50
local CTA_BG_HOVER       = 0.20
local CTA_BORDER_HOVER   = 0.80

-- Row-height constant for GUI:CreateEditBox (label-above style).
local EDIT_BOX_ROW_H = 56

-- Semantic palette for content-type categories. Tints card title text and
-- could be reused for category badges later.
local CATEGORY_COLORS = {
    group    = {r = 0.65, g = 0.45, b = 0.95, a = 1},  -- purple
    identity = {r = 0.55, g = 0.75, b = 0.95, a = 1},  -- light blue
    health   = {r = 0.95, g = 0.35, b = 0.35, a = 1},  -- red
    power    = {r = 0.35, g = 0.55, b = 0.95, a = 1},  -- blue
    shields  = {r = 0.45, g = 0.85, b = 0.85, a = 1},  -- cyan
    status   = {r = 0.65, g = 0.65, b = 0.65, a = 1},  -- gray
    threat   = {r = 0.95, g = 0.65, b = 0.25, a = 1},  -- orange
}

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
    "group", "identity", "health", "power", "shields", "status", "threat",
}

local CONTENT_CATEGORY_LABELS = {
    identity = L["Identity & Roster"],
    health   = L["Health"],
    power    = L["Power"],
    shields  = L["Shields & Heals"],
    status   = L["Status"],
    threat   = L["Threat & Range"],
    group    = L["Group"],
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
    -- Group
    { key = "group",             label = L["Text Group"],                 category = "group"    },
}

local function FindContentType(key)
    for _, t in ipairs(CONTENT_TYPES) do
        if t.key == key then return t end
    end
end

-- Auto-number duplicate-type elements: first one stays unlabeled (renders as
-- just the type name), subsequent ones get "TypeName #2", "Name #3", etc.
-- N is the next available integer >= 2 in existing labels matching the
-- "TypeName #N" pattern, so delete + re-add doesn't produce duplicates.
local function ComputeAutoLabel(tdDB, ct)
    if not ct then return "" end
    local typeLabel = ct.label or ct.key
    -- Count existing elements with the same contentType
    local hasAny = false
    for _, e in ipairs(tdDB.elements) do
        if e.contentType == ct.key then
            hasAny = true
            break
        end
    end
    if not hasAny then return "" end  -- first of its type, no label needed
    -- Find next available #N
    local maxN = 1
    local escapedLabel = typeLabel:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local pattern = "^" .. escapedLabel .. " #(%d+)$"
    for _, e in ipairs(tdDB.elements) do
        if e.contentType == ct.key and e.label then
            local n = tonumber(e.label:match(pattern))
            if n and n > maxN then maxN = n end
        end
    end
    return typeLabel .. " #" .. (maxN + 1)
end

-- ============================================================
-- BODY SECTION HELPERS
-- Shared layout primitives used by the Content / Appearance / Position
-- section builders.
-- ============================================================

local SECTION_LABEL_HEIGHT = 18
-- Y-decrement per field row. GUI helpers vary in height (CreateDropdown ~36,
-- CreateSlider ~30, CreateEditBox ~48 with label-above), so this value is
-- tuned to clear the tallest common widget without being wasteful. The
-- custom_static row uses an even taller decrement (see BuildContentSection)
-- because CreateEditBox renders its label above the input.
local FIELD_ROW_HEIGHT = 44
local SECTION_GAP = 8

local function CreateSectionLabel(GUI, parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(fs, 9, "")  -- no outline; subtle dim grey caption
    fs:SetText(text:upper())
    fs:SetTextColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, C_TEXT_DIM.a)
    return fs
end

-- Forward-declared so BuildContentSection's group branch can reference the
-- picker that's defined later in the file.
local BuildPicker

-- Returns the y-offset where the next section should start (negative, goes down).
-- tdDB / state / page are needed by the Text Group branch so its nested
-- add/remove callbacks can trigger a card-list re-render.
-- `card` is the parent settings group; the Label edit box updates card.title.
local function BuildContentSection(GUI, parent, elem, tdDB, state, page, card, yStart)
    local label = CreateSectionLabel(GUI, parent, L["Content"])
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yStart)
    local y = yStart - SECTION_LABEL_HEIGHT

    local ct = FindContentType(elem.contentType)
    if not ct then return y end

    -- ── Label (optional) ─────────────────────────────────────
    -- A user-friendly name for this element. Falls back to the content type
    -- name when empty. Used in the card header title and the Anchor To
    -- dropdown's options.
    elem.label = elem.label or ""
    local labelEdit = GUI:CreateEditBox(parent, L["Label (optional)"], elem, "label", function()
        if card and card.title then
            local activeCT = FindContentType(elem.contentType)
            local displayName = (elem.label and elem.label ~= "" and elem.label)
                or (activeCT and activeCT.label)
                or elem.contentType
            card.title:SetText(displayName)
            -- Re-apply the category tint so SetText doesn't reset it back to
            -- the default font colour.
            local cc = card.titleCatColor
            if cc then
                card.title:SetTextColor(cc.r, cc.g, cc.b, cc.a)
            else
                card.title:SetTextColor(C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a)
            end
            -- Refresh banner so the appended target name (if any other card
            -- anchors TO this one) reflects the new label.
            if card.UpdateMeta then card:UpdateMeta() end
        end
        -- Every OTHER card has an Anchor To dropdown that lists this element
        -- by label — force a full rebuild so they pick up the new label.
        -- Defer to the next frame so the rebuild happens AFTER the current
        -- click event finishes resolving (focus-loss fires mid-click; rebuilding
        -- synchronously here destroys the frames the click is still landing on).
        if state and DF.TextDesigner.FullRebuildCards then
            C_Timer.After(0, function()
                DF.TextDesigner.FullRebuildCards(GUI, page, tdDB, state)
            end)
        end
    end, 200)
    labelEdit:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    -- CreateEditBox is label-above style; row is taller than other widgets.
    y = y - EDIT_BOX_ROW_H

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
        local edit = GUI:CreateEditBox(parent, L["Text"], elem, "staticText", function() end, 240)
        edit:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        -- CreateEditBox renders its label ABOVE the input, so the row is
        -- taller than other widgets. Use a custom y-decrement instead of
        -- FIELD_ROW_HEIGHT.
        y = y - EDIT_BOX_ROW_H

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

    -- Text Group: concatenates 2+ child content values with a user separator.
    -- Phase 1 stores groupItems / groupSeparator on the element; Phase 2 will
    -- wire the runtime renderer.
    elseif ct.key == "group" then
        elem.groupItems = elem.groupItems or {}
        elem.groupSeparator = elem.groupSeparator or " / "

        local mediaPath = "Interface\\AddOns\\DandersFrames\\Media\\Icons\\"

        -- Helper to re-render the whole card list when items change. Uses
        -- the full rebuild path so every other card's Anchor To dropdown
        -- and group items list refresh in lockstep.
        -- Deferred via C_Timer.After(0, ...) so the rebuild happens AFTER the
        -- current click event finishes — synchronous rebuilds mid-click destroy
        -- the frames the click is still landing on.
        local function ReRender()
            if state and DF.TextDesigner.FullRebuildCards then
                C_Timer.After(0, function()
                    DF.TextDesigner.FullRebuildCards(GUI, page, tdDB, state)
                end)
            end
        end

        -- Separator input (CreateEditBox renders its label ABOVE the input)
        local sepEdit = GUI:CreateEditBox(parent, L["Separator"], elem, "groupSeparator", function() end, 120)
        sepEdit:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        y = y - EDIT_BOX_ROW_H

        -- Items label
        local itemsLabel = parent:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(itemsLabel, 9, "")
        itemsLabel:SetText(L["Items"]:upper())
        itemsLabel:SetTextColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, C_TEXT_DIM.a)
        itemsLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        y = y - 16

        -- Items list — one row per item in elem.groupItems
        if #elem.groupItems == 0 then
            local emptyLbl = parent:CreateFontString(nil, "OVERLAY")
            GUI:SetSettingsFont(emptyLbl, 10, "")
            emptyLbl:SetText(L["No items yet"])
            emptyLbl:SetTextColor(0.5, 0.5, 0.5)
            emptyLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 26, y)
            y = y - 18
        else
            for itemIdx, itemKey in ipairs(elem.groupItems) do
                local itemCT = FindContentType(itemKey)
                local itemRow = CreateFrame("Frame", nil, parent)
                itemRow:SetHeight(20)
                itemRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y)
                itemRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -22, y)

                local itemLabel = itemRow:CreateFontString(nil, "OVERLAY")
                GUI:SetSettingsFont(itemLabel, 10, "")
                itemLabel:SetPoint("LEFT", itemRow, "LEFT", 4, 0)
                itemLabel:SetText(itemIdx .. ". " .. (itemCT and itemCT.label or itemKey))
                itemLabel:SetTextColor(0.9, 0.9, 0.9)

                -- Remove button — hand-drawn X cross (smaller variant for in-row).
                -- Two rotated SetColorTexture lines mirror AuraDesigner's pattern
                -- (AuraDesigner/Options.lua:4412-4433).
                local removeBtn = CreateFrame("Button", nil, itemRow, "BackdropTemplate")
                removeBtn:SetSize(16, 16)
                removeBtn:SetPoint("RIGHT", itemRow, "RIGHT", -4, 0)
                local rxSize, rxThick = 10, 1.5
                local rline1 = removeBtn:CreateTexture(nil, "OVERLAY")
                rline1:SetSize(rxSize, rxThick)
                rline1:SetPoint("CENTER", 0, 0)
                rline1:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
                rline1:SetRotation(math.rad(45))
                local rline2 = removeBtn:CreateTexture(nil, "OVERLAY")
                rline2:SetSize(rxSize, rxThick)
                rline2:SetPoint("CENTER", 0, 0)
                rline2:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
                rline2:SetRotation(math.rad(-45))
                removeBtn:SetScript("OnEnter", function()
                    rline1:SetColorTexture(C_DESTRUCTIVE_HOVER.r, C_DESTRUCTIVE_HOVER.g, C_DESTRUCTIVE_HOVER.b, C_DESTRUCTIVE_HOVER.a)
                    rline2:SetColorTexture(C_DESTRUCTIVE_HOVER.r, C_DESTRUCTIVE_HOVER.g, C_DESTRUCTIVE_HOVER.b, C_DESTRUCTIVE_HOVER.a)
                end)
                removeBtn:SetScript("OnLeave", function()
                    rline1:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
                    rline2:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
                end)
                local capturedIdx = itemIdx
                removeBtn:SetScript("OnClick", function()
                    table.remove(elem.groupItems, capturedIdx)
                    ReRender()
                end)

                -- Up arrow — moves this item one slot earlier in the list.
                -- Hidden on the first row (nothing to swap into).
                local upBtn = CreateFrame("Button", nil, itemRow)
                upBtn:SetSize(14, 14)
                upBtn:SetPoint("RIGHT", removeBtn, "LEFT", -8, 0)
                local upIcon = upBtn:CreateTexture(nil, "OVERLAY")
                upIcon:SetAllPoints()
                upIcon:SetTexture(mediaPath .. "expand_more")
                upIcon:SetRotation(math.pi)  -- 180° = up
                upIcon:SetVertexColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b)
                upBtn:SetScript("OnEnter", function() upIcon:SetVertexColor(1, 1, 1) end)
                upBtn:SetScript("OnLeave", function() upIcon:SetVertexColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b) end)
                upBtn:SetScript("OnClick", function()
                    if capturedIdx > 1 then
                        elem.groupItems[capturedIdx], elem.groupItems[capturedIdx - 1] =
                            elem.groupItems[capturedIdx - 1], elem.groupItems[capturedIdx]
                        ReRender()
                    end
                end)
                if capturedIdx == 1 then upBtn:Hide() end

                -- Down arrow — moves this item one slot later in the list.
                -- Hidden on the last row.
                local downBtn = CreateFrame("Button", nil, itemRow)
                downBtn:SetSize(14, 14)
                downBtn:SetPoint("RIGHT", upBtn, "LEFT", -2, 0)
                local downIcon = downBtn:CreateTexture(nil, "OVERLAY")
                downIcon:SetAllPoints()
                downIcon:SetTexture(mediaPath .. "expand_more")
                downIcon:SetVertexColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b)
                downBtn:SetScript("OnEnter", function() downIcon:SetVertexColor(1, 1, 1) end)
                downBtn:SetScript("OnLeave", function() downIcon:SetVertexColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b) end)
                downBtn:SetScript("OnClick", function()
                    if capturedIdx < #elem.groupItems then
                        elem.groupItems[capturedIdx], elem.groupItems[capturedIdx + 1] =
                            elem.groupItems[capturedIdx + 1], elem.groupItems[capturedIdx]
                        ReRender()
                    end
                end)
                if capturedIdx == #elem.groupItems then downBtn:Hide() end

                y = y - 22
            end
        end

        -- Add Item button — opens a picker that excludes the "group" type
        -- (no nested groups). The picker is cached on the card so repeated
        -- clicks reuse the same frame instead of spawning new offscreen ones.
        local addItemBtn
        addItemBtn = GUI:CreateButton(parent, "+ " .. L["Add Item"], 100, 22, function()
            if not BuildPicker then return end
            if card and not card._addItemPicker then
                card._addItemPicker = BuildPicker(GUI, parent, tdDB, function(typeKey)
                    table.insert(elem.groupItems, typeKey)
                    ReRender()
                end, "group")
            end
            local picker = card and card._addItemPicker
            if not picker then return end
            if picker:IsShown() then
                picker:Hide()
            else
                -- Anchor left-aligned: the Add Item button sits on the LEFT
                -- of the card body, so the dropdown extends RIGHT and DOWN.
                picker:Open(addItemBtn, "left")
            end
        end)
        addItemBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y)

        -- Theme-tint the button to match AuraDesigner's CTA pattern.
        do
            local tc = GUI:GetThemeColor()
            if addItemBtn.SetBackdropColor then
                addItemBtn:SetBackdropColor(tc.r * CTA_BG_RESTING, tc.g * CTA_BG_RESTING, tc.b * CTA_BG_RESTING, 1)
                addItemBtn:SetBackdropBorderColor(tc.r * CTA_BORDER_RESTING, tc.g * CTA_BORDER_RESTING, tc.b * CTA_BORDER_RESTING, 1)
                addItemBtn:HookScript("OnEnter", function(self)
                    local c = GUI:GetThemeColor()
                    self:SetBackdropColor(c.r * CTA_BG_HOVER, c.g * CTA_BG_HOVER, c.b * CTA_BG_HOVER, 1)
                    self:SetBackdropBorderColor(c.r * CTA_BORDER_HOVER, c.g * CTA_BORDER_HOVER, c.b * CTA_BORDER_HOVER, 1)
                end)
                addItemBtn:HookScript("OnLeave", function(self)
                    local c = GUI:GetThemeColor()
                    self:SetBackdropColor(c.r * CTA_BG_RESTING, c.g * CTA_BG_RESTING, c.b * CTA_BG_RESTING, 1)
                    self:SetBackdropBorderColor(c.r * CTA_BORDER_RESTING, c.g * CTA_BORDER_RESTING, c.b * CTA_BORDER_RESTING, 1)
                end)
            end
        end
        y = y - 32
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

local function CreateAnchorGrid(GUI, parent, elem, card)
    local grid = CreateFrame("Frame", nil, parent)
    grid:SetSize(60, 60)

    local btns = {}
    local function ApplyButtonState(b, active)
        if active then
            local tc = GUI:GetThemeColor()
            b:SetBackdropColor(tc.r, tc.g, tc.b, 0.40)
            b:SetBackdropBorderColor(tc.r, tc.g, tc.b, 0.90)
        else
            b:SetBackdropColor(C_PANEL.r, C_PANEL.g, C_PANEL.b, 0.80)
            b:SetBackdropBorderColor(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.50)
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
                if card and card.UpdateMeta then card:UpdateMeta() end
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
-- `card` is accepted for signature consistency with BuildContentSection; not used.
local function BuildAppearanceSection(GUI, parent, elem, card, yStart)
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

    -- Color picker + Use Class Color toggle (stacked vertically so they
    -- don't overflow the now-narrower card body).
    -- CreateColorPicker signature: (parent, label, dbTable, dbKey, hasAlpha, callback, ...)
    local colorPicker = GUI:CreateColorPicker(parent, L["Color"], elem, "color", true, function() end)
    colorPicker:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    local classColorCheck = GUI:CreateCheckbox(parent, L["Use Class Color"], elem, "useClassColor", function()
        if elem.useClassColor then
            if colorPicker.Disable then colorPicker:Disable() end
            colorPicker:SetAlpha(0.4)
        else
            if colorPicker.Enable then colorPicker:Enable() end
            colorPicker:SetAlpha(1)
        end
    end)
    classColorCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    -- Apply initial grayed state if class color is on
    if elem.useClassColor then
        if colorPicker.Disable then colorPicker:Disable() end
        colorPicker:SetAlpha(0.4)
    end

    return y - SECTION_GAP
end

-- Build the Anchor To dropdown's options table. Returns {key=label} where
-- the FRAME sentinel anchors to the unit frame and integer-string keys
-- anchor to another element's id. Excludes self and any transitive
-- descendant (cycle prevention).
local function BuildAnchorTargets(tdDB, currentElem)
    local descendants = {}
    local function MarkDescendants(rootID)
        for _, e in ipairs(tdDB.elements) do
            if e.anchorTo and tostring(e.anchorTo) == tostring(rootID) and not descendants[e.id] then
                descendants[e.id] = true
                MarkDescendants(e.id)
            end
        end
    end
    MarkDescendants(currentElem.id)

    local opts = { FRAME = L["Frame"] }
    for _, other in ipairs(tdDB.elements) do
        if other.id ~= currentElem.id and not descendants[other.id] then
            local optLabel
            if other.label and other.label ~= "" then
                optLabel = other.label
            else
                local ct = FindContentType(other.contentType)
                optLabel = ct and ct.label or other.contentType
            end
            opts[tostring(other.id)] = optLabel
        end
    end
    return opts
end

-- Returns the y-offset where the next section should start (negative, goes down).
-- `card` is forwarded into CreateAnchorGrid and into each position widget's
-- callback so the header banner ("CENTER · 0,0 · → target") can refresh live
-- whenever the user changes anchor / offsets / anchor target.
local function BuildPositionSection(GUI, parent, elem, tdDB, card, yStart)
    local label = CreateSectionLabel(GUI, parent, L["Position"])
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yStart)
    local y = yStart - SECTION_LABEL_HEIGHT

    -- Defaults
    elem.anchor = elem.anchor or "CENTER"
    elem.offsetX = elem.offsetX or 0
    elem.offsetY = elem.offsetY or 0
    elem.frameLevel = elem.frameLevel or 25
    elem.frameStrata = elem.frameStrata or "INHERIT"
    elem.anchorTo = elem.anchorTo or "FRAME"

    -- Shared callback: every position-related widget needs to refresh the
    -- card's header banner so the "ANCHOR · X,Y · → target" summary stays
    -- in sync with the live values.
    local function metaCB() if card and card.UpdateMeta then card:UpdateMeta() end end

    -- Anchor grid first (stacked, not side-by-side). The card body is now
    -- ~half the page width so the previous side-by-side layout would overflow.
    -- Grid is 60×60, with a small label beneath; advance y by grid + label + gap.
    local grid = CreateAnchorGrid(GUI, parent, elem, card)
    grid:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y - 4)
    local gridLabel = parent:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(gridLabel, 8, "")
    gridLabel:SetText(L["Anchor"])
    gridLabel:SetPoint("TOP", grid, "BOTTOM", 0, -2)
    gridLabel:SetTextColor(0.6, 0.6, 0.6)
    -- Grid (60) + label gap (2) + label (10) + bottom gap (8) ≈ 80
    y = y - 80

    -- Stacked sliders + dropdowns (full body width)
    local xSlider = GUI:CreateSlider(parent, L["Offset X"], -200, 200, 1, elem, "offsetX", metaCB)
    xSlider:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    local ySlider = GUI:CreateSlider(parent, L["Offset Y"], -200, 200, 1, elem, "offsetY", metaCB)
    ySlider:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    local lvlSlider = GUI:CreateSlider(parent, L["Frame Level"], 1, 200, 1, elem, "frameLevel", function() end)
    lvlSlider:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    local strataOpts = {
        INHERIT = L["Inherit"],
        LOW = "LOW",
        MEDIUM = "MEDIUM",
        HIGH = "HIGH",
        DIALOG = "DIALOG",
    }
    local strataDrop = GUI:CreateDropdown(parent, L["Frame Strata"], strataOpts, elem, "frameStrata", function() end)
    strataDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    -- Anchor To: target element (or the unit frame). Options are computed
    -- dynamically and exclude self + transitive descendants to prevent cycles.
    local anchorTargets = BuildAnchorTargets(tdDB, elem)
    local anchorToDrop = GUI:CreateDropdown(parent, L["Anchor To"], anchorTargets, elem, "anchorTo", metaCB)
    anchorToDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    y = y - FIELD_ROW_HEIGHT

    return y - SECTION_GAP
end

-- ============================================================
-- ADD ELEMENT PICKER
-- A floating dropdown: search input, category pill row, grouped list.
-- Calls onPick(typeKey) when the user selects a type. Closes on pick.
-- Click the Add Element button again to dismiss without picking.
-- ============================================================

-- BuildPicker is forward-declared above so BuildContentSection's group
-- branch can reference it. Assign the implementation to the upvalue.
function BuildPicker(GUI, parent, tdDB, onPick, excludeKey)
    local drop = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    drop:SetFrameStrata("FULLSCREEN_DIALOG")
    drop:SetClampedToScreen(true)
    drop:SetSize(280, 380)
    ApplyBackdrop(drop, C_BACKGROUND, C_BORDER)
    drop:Hide()

    -- ── Click-outside overlay ────────────────────────────────
    -- A transparent fullscreen catcher that closes the picker when the user
    -- clicks anywhere outside it. Pattern mirrors AuraDesigner's picker.
    local overlay = CreateFrame("Button", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN")  -- below FULLSCREEN_DIALOG so drop stays on top
    overlay:EnableMouse(true)
    overlay:Hide()
    overlay:SetScript("OnClick", function()
        drop:Hide()
    end)
    drop._overlay = overlay

    -- ESC closes the picker as well.
    drop:EnableKeyboard(true)
    drop:SetPropagateKeyboardInput(true)
    drop:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            drop:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- ── Themed search bar ────────────────────────────────────
    -- Mirrors the global settings search bar pattern (Features/Search.lua:1001-1100).
    -- Wrapper Frame holds a magnifying glass icon, EditBox, placeholder, and clear-X.
    local searchBar = CreateFrame("Frame", nil, drop, "BackdropTemplate")
    searchBar:SetSize(248, 28)
    searchBar:SetPoint("TOPLEFT", drop, "TOPLEFT", 16, -12)
    searchBar:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    searchBar:SetBackdropColor(0, 0, 0, 0.7)
    searchBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local searchIcon = searchBar:CreateTexture(nil, "OVERLAY")
    searchIcon:SetPoint("LEFT", 6, 0)
    searchIcon:SetSize(12, 12)
    searchIcon:SetTexture("Interface\\AddOns\\DandersFrames\\Media\\Icons\\search")
    searchIcon:SetVertexColor(0.6, 0.6, 0.6)

    local searchBox = CreateFrame("EditBox", nil, searchBar)
    searchBox:SetPoint("LEFT", 22, 0)
    searchBox:SetPoint("RIGHT", -24, 0)
    searchBox:SetHeight(20)
    searchBox:SetFontObject(DFFontHighlightSmall)
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(2, 2, 0, 0)
    drop.searchBox = searchBox

    local searchPlaceholder = searchBar:CreateFontString(nil, "OVERLAY", "DFFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", 24, 0)
    searchPlaceholder:SetText(L["Search..."])
    searchPlaceholder:SetTextColor(0.5, 0.5, 0.5)

    local clearBtn = CreateFrame("Button", nil, searchBar)
    clearBtn:SetSize(16, 16)
    clearBtn:SetPoint("RIGHT", -4, 0)
    local clearIcon = clearBtn:CreateTexture(nil, "OVERLAY")
    clearIcon:SetAllPoints()
    clearIcon:SetTexture("Interface\\AddOns\\DandersFrames\\Media\\Icons\\close")
    clearIcon:SetVertexColor(0.5, 0.5, 0.5)
    clearBtn:SetScript("OnEnter", function() clearIcon:SetVertexColor(1, 0.3, 0.3) end)
    clearBtn:SetScript("OnLeave", function() clearIcon:SetVertexColor(0.5, 0.5, 0.5) end)
    clearBtn:Hide()

    searchBox:SetScript("OnEditFocusGained", function()
        local tc = GUI:GetThemeColor()
        searchBar:SetBackdropBorderColor(tc.r, tc.g, tc.b, 1)
        searchPlaceholder:Hide()
    end)
    searchBox:SetScript("OnEditFocusLost", function()
        searchBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        if searchBox:GetText() == "" then searchPlaceholder:Show() end
    end)

    -- ── Pill row (category filters) ─────────────────────────
    -- Sized to the dropdown width minus side padding so flow-layout can wrap.
    local PILL_ROW_PAD = 16
    local pillRow = CreateFrame("Frame", nil, drop)
    pillRow:SetPoint("TOPLEFT", searchBar, "BOTTOMLEFT", 0, -10)
    pillRow:SetPoint("TOPRIGHT", drop, "TOPRIGHT", -PILL_ROW_PAD, 0)
    pillRow:SetHeight(24)
    local pills = {}

    local CHIP_H, CHIP_GAP, CHIP_ROW_GAP = 24, 4, 4

    -- Hoisted so MakePill's hover handlers can see it lexically. Set to the
    -- starting filter; ApplyPillState() initializes visuals after pills exist.
    local activePill = "_all"

    local function MakePill(label, key)
        local p = CreateFrame("Button", nil, pillRow, "BackdropTemplate")
        p:SetHeight(CHIP_H)
        ApplyBackdrop(p, C_PANEL, C_BORDER)
        local fs = p:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(fs, 10, "")
        fs:SetPoint("CENTER")
        fs:SetText(label)
        p:SetWidth(fs:GetStringWidth() + 18)
        p.key = key
        p.fs = fs
        p:SetScript("OnEnter", function(self)
            if self.key ~= activePill then
                self:SetBackdropColor(C_HOVER.r, C_HOVER.g, C_HOVER.b, 1)
                self:SetBackdropBorderColor(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.8)
            end
        end)
        p:SetScript("OnLeave", function(self)
            if self.key ~= activePill then
                self:SetBackdropColor(C_PANEL.r, C_PANEL.g, C_PANEL.b, C_PANEL.a)
                self:SetBackdropBorderColor(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.5)
            end
        end)
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

    local function ApplyPillState()
        local tc = GUI:GetThemeColor()
        for _, p in ipairs(pills) do
            if p.key == activePill then
                p:SetBackdropColor(tc.r, tc.g, tc.b, 0.20)
                p:SetBackdropBorderColor(tc.r, tc.g, tc.b, 0.50)
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
    scrollFrame:SetPoint("TOPLEFT", pillRow, "BOTTOMLEFT", 4, -10)
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
        it:SetSize(240, 22)
        it:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
        do
            local tc = GUI:GetThemeColor()
            it:SetBackdropColor(tc.r, tc.g, tc.b, 0)
        end
        local fs = it:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(fs, 11, "")
        fs:SetPoint("LEFT", it, "LEFT", 14, 0)
        it.fs = fs
        it:SetScript("OnEnter", function(self)
            local tc = GUI:GetThemeColor()
            self:SetBackdropColor(tc.r, tc.g, tc.b, 0.30)
        end)
        it:SetScript("OnLeave", function(self)
            local tc = GUI:GetThemeColor()
            self:SetBackdropColor(tc.r, tc.g, tc.b, 0)
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
        GUI:SetSettingsFont(h, 10, "")
        h:SetJustifyH("LEFT")
        headerPool[#headerPool+1] = h
        return h
    end

    -- Hairline divider pool — one thin texture between category sections.
    local dividerPool = {}
    local function AcquireDivider()
        for _, d in ipairs(dividerPool) do
            if not d:IsShown() then return d end
        end
        local d = scrollChild:CreateTexture(nil, "ARTWORK")
        d:SetColorTexture(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.3)
        d:SetHeight(1)
        dividerPool[#dividerPool+1] = d
        return d
    end

    local function HideAll()
        for _, it in ipairs(itemPool) do it:Hide() end
        for _, h in ipairs(headerPool) do h:Hide() end
        for _, d in ipairs(dividerPool) do d:Hide() end
    end

    local function RenderList()
        HideAll()
        local query = (searchBox:GetText() or ""):lower()
        query = query:match("^%s*(.-)%s*$") or ""

        local y = -2
        local renderedSection = false
        for _, cat in ipairs(CONTENT_CATEGORIES) do
            if activePill == "_all" or activePill == cat then
                local matches = {}
                for _, t in ipairs(CONTENT_TYPES) do
                    if t.category == cat and t.key ~= excludeKey then
                        if query == "" or t.label:lower():find(query, 1, true) then
                            matches[#matches+1] = t
                        end
                    end
                end
                if #matches > 0 then
                    -- Hairline divider above every section except the first
                    if renderedSection then
                        local sep = AcquireDivider()
                        sep:ClearAllPoints()
                        sep:SetPoint("LEFT", scrollChild, "LEFT", 8, 0)
                        sep:SetPoint("RIGHT", scrollChild, "RIGHT", -8, 0)
                        sep:SetPoint("TOP", scrollChild, "TOP", 0, y - 2)
                        sep:Show()
                        y = y - 8
                    end
                    local h = AcquireHeader()
                    h:ClearAllPoints()
                    h:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, y)
                    h:SetText(CONTENT_CATEGORY_LABELS[cat]:upper())
                    h:SetTextColor(C_TEXT.r, C_TEXT.g, C_TEXT.b, 1)
                    h:Show()
                    y = y - 16
                    for _, t in ipairs(matches) do
                        local it = AcquireItem()
                        it:ClearAllPoints()
                        it:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, y)
                        it.fs:SetText(t.label)
                        local catColor = CATEGORY_COLORS[t.category]
                        if catColor then
                            it.fs:SetTextColor(catColor.r, catColor.g, catColor.b, catColor.a)
                        else
                            it.fs:SetTextColor(0.95, 0.95, 0.95)
                        end
                        it:SetScript("OnClick", function()
                            drop:Hide()
                            if onPick then onPick(t.key) end
                        end)
                        it:Show()
                        y = y - 24
                    end
                    y = y - 4
                    renderedSection = true
                end
            end
        end
        scrollChild:SetHeight(math.max(1, -y + 4))
    end

    searchBox:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        if text and text ~= "" then
            searchPlaceholder:Hide()
            clearBtn:Show()
        else
            if not self:HasFocus() then searchPlaceholder:Show() end
            clearBtn:Hide()
        end
        RenderList()
    end)

    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
    end)

    for _, p in ipairs(pills) do
        p:SetScript("OnClick", function(self)
            activePill = self.key
            ApplyPillState()
            RenderList()
        end)
    end

    -- `side` is optional. "right" (default) anchors TOPRIGHT-to-BOTTOMRIGHT
    -- so the dropdown extends LEFT and DOWN — correct for buttons on the right
    -- side of the controls bar. "left" anchors TOPLEFT-to-BOTTOMLEFT so the
    -- dropdown extends RIGHT and DOWN — correct for the in-card Add Item
    -- button which sits on the LEFT of the card body.
    function drop:Open(anchor, side)
        searchBox:SetText("")
        searchPlaceholder:Show()
        clearBtn:Hide()
        activePill = "_all"
        ApplyPillState()
        RenderList()
        drop:ClearAllPoints()
        if side == "left" then
            drop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        else
            drop:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        end
        drop:Show()
        if overlay then overlay:Show() end
        searchBox:SetFocus()
    end

    drop:SetScript("OnHide", function()
        if overlay then overlay:Hide() end
        searchBox:ClearFocus()
        searchBox:SetText("")
        searchPlaceholder:Show()
        clearBtn:Hide()
    end)

    return drop
end

-- ============================================================
-- ELEMENT CARD
-- A collapsible card representing one text element. Built using the same
-- direct-frame pattern as AuraDesigner's CreateEffectCard
-- (AuraDesigner/Options.lua:4278-4879):
--   - Outer card  = layout-only Frame, no backdrop
--   - Header      = BackdropTemplate Button with its own backdrop + hover
--   - Body        = separate BackdropTemplate Frame with its own backdrop
-- Body sections: Content / Appearance / Position.
-- ============================================================

-- AD-style card builder. Returns (card, totalCardH). Caller advances its
-- y-cursor with totalCardH. The card is layout-only; the header and body each
-- own their own backdrop so there's no underlying surface bleeding through.
--
-- Section builder signatures (preserved from before the AD-clone refactor):
--   BuildContentSection(GUI, parent, elem, tdDB, state, page, card, yStart)
--   BuildAppearanceSection(GUI, parent, elem, card, yStart)
--   BuildPositionSection(GUI, parent, elem, tdDB, card, yStart)
local function CreateTextElementCard(GUI, parent, yPos, elem, tdDB, state, page)
    local HEADER_HEIGHT = 30

    -- Outer card: layout-only, no backdrop
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, yPos)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, yPos)

    card._tdDB = tdDB
    card._state = state
    card._GUI = GUI
    card._page = page
    card._elem = elem

    -- ── HEADER ───────────────────────────────────────────────
    local header = CreateFrame("Button", nil, card, "BackdropTemplate")
    header:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    header:SetBackdropColor(C_ELEMENT.r, C_ELEMENT.g, C_ELEMENT.b, C_ELEMENT.a)
    header:SetBackdropBorderColor(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.5)

    header:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C_HOVER.r, C_HOVER.g, C_HOVER.b, C_HOVER.a)
    end)
    header:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C_ELEMENT.r, C_ELEMENT.g, C_ELEMENT.b, C_ELEMENT.a)
    end)
    card.header = header

    -- Collapse arrow on the LEFT
    local mediaPath = "Interface\\AddOns\\DandersFrames\\Media\\Icons\\"
    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("LEFT", header, "LEFT", 8, 0)
    do
        local tc = GUI:GetThemeColor()
        arrow:SetVertexColor(tc.r, tc.g, tc.b)
    end
    card.collapseArrow = arrow

    -- Category-color chip (replaces AD's spell icon)
    local ct = FindContentType(elem.contentType)
    local catColor = ct and CATEGORY_COLORS[ct.category]
    local chip = header:CreateTexture(nil, "OVERLAY")
    chip:SetSize(4, 18)
    chip:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
    if catColor then
        chip:SetColorTexture(catColor.r, catColor.g, catColor.b, catColor.a)
    else
        chip:SetColorTexture(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, 1)
    end

    -- Title text
    local title = header:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(title, 11, "OUTLINE")
    title:SetPoint("LEFT", chip, "RIGHT", 8, 0)
    local displayName = (elem.label and elem.label ~= "" and elem.label) or (ct and ct.label) or elem.contentType
    title:SetText(displayName)
    if catColor then
        title:SetTextColor(catColor.r, catColor.g, catColor.b, catColor.a)
        card.titleCatColor = catColor
    else
        title:SetTextColor(C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a)
    end
    card.title = title

    -- Meta line
    local meta = header:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(meta, 9, "")
    meta:SetPoint("LEFT", title, "RIGHT", 8, 0)
    meta:SetTextColor(0.55, 0.6, 0.7)
    card.meta = meta

    -- ── ACTION ICONS (right side of header) ──────────────────
    -- Hand-drawn X delete (matches AD pattern)
    local ICON_SIZE = 18
    local ICON_GAP = 4

    local deleteBtn = CreateFrame("Button", nil, header)
    deleteBtn:SetSize(22, 22)
    deleteBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    local dxSize, dxThick = 12, 2
    local dline1 = deleteBtn:CreateTexture(nil, "OVERLAY")
    dline1:SetSize(dxSize, dxThick)
    dline1:SetPoint("CENTER")
    dline1:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
    dline1:SetRotation(math.rad(45))
    local dline2 = deleteBtn:CreateTexture(nil, "OVERLAY")
    dline2:SetSize(dxSize, dxThick)
    dline2:SetPoint("CENTER")
    dline2:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
    dline2:SetRotation(math.rad(-45))
    deleteBtn:SetScript("OnEnter", function()
        dline1:SetColorTexture(C_DESTRUCTIVE_HOVER.r, C_DESTRUCTIVE_HOVER.g, C_DESTRUCTIVE_HOVER.b, C_DESTRUCTIVE_HOVER.a)
        dline2:SetColorTexture(C_DESTRUCTIVE_HOVER.r, C_DESTRUCTIVE_HOVER.g, C_DESTRUCTIVE_HOVER.b, C_DESTRUCTIVE_HOVER.a)
    end)
    deleteBtn:SetScript("OnLeave", function()
        dline1:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
        dline2:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
    end)
    card.deleteBtn = deleteBtn

    -- Eye icon (visibility toggle) — TD-specific, left of delete
    local eyeBtn = CreateFrame("Button", nil, header)
    eyeBtn:SetSize(ICON_SIZE, ICON_SIZE)
    eyeBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -ICON_GAP, 0)
    local eyeIcon = eyeBtn:CreateTexture(nil, "OVERLAY")
    eyeIcon:SetAllPoints()
    local function updateEyeIcon()
        if elem.enabled then
            eyeIcon:SetTexture(mediaPath .. "visibility")
            eyeIcon:SetVertexColor(0.95, 0.95, 0.95)
        else
            eyeIcon:SetTexture(mediaPath .. "visibility_off")
            eyeIcon:SetVertexColor(0.45, 0.45, 0.45)
        end
    end
    updateEyeIcon()
    eyeBtn:SetScript("OnEnter", function() if elem.enabled then eyeIcon:SetVertexColor(1,1,1) end end)
    eyeBtn:SetScript("OnLeave", function() updateEyeIcon() end)
    card.eyeBtn = eyeBtn

    -- Click-through prevention on action icons
    for _, btn in ipairs({eyeBtn, deleteBtn}) do
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetFrameLevel(header:GetFrameLevel() + 5)
    end

    -- Eye OnClick
    eyeBtn:SetScript("OnClick", function()
        elem.enabled = not elem.enabled
        updateEyeIcon()
        DF:Debug("TD", "Element %d enabled=%s", elem.id, tostring(elem.enabled))
    end)

    -- Delete OnClick (instant, no popup)
    deleteBtn:SetScript("OnClick", function()
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
        if DF.TextDesigner.FullRebuildCards then
            DF.TextDesigner.FullRebuildCards(capturedGUI, capturedPage, capturedTdDB, capturedState)
        end
        DF:Debug("TD", "Deleted element id=%d (remaining=%d)",
            elem.id, #capturedTdDB.elements)
    end)

    -- ── BODY ─────────────────────────────────────────────────
    local body = CreateFrame("Frame", nil, card, "BackdropTemplate")
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    body:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    body:SetBackdropColor(C_BODY_BG.r, C_BODY_BG.g, C_BODY_BG.b, C_BODY_BG.a)
    body:SetBackdropBorderColor(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.3)
    card.body = body

    -- Build content sections inside body. BuildAppearanceSection's signature
    -- is (GUI, parent, elem, card, yStart) — the section builders were not
    -- changed in Phase 2.1.
    local yEnd = BuildContentSection(GUI, body, elem, tdDB, state, page, card, -10)
    yEnd = BuildAppearanceSection(GUI, body, elem, card, yEnd)
    yEnd = BuildPositionSection(GUI, body, elem, tdDB, card, yEnd)
    local bodyHeight = math.max(1, -yEnd + 10)
    body:SetHeight(bodyHeight)

    -- ── COLLAPSE STATE ───────────────────────────────────────
    local cardKey = "td_elem_" .. tostring(elem.id)
    local savedStates = GUI:GetCollapsedGroups()
    card.collapsed = savedStates[cardKey] == true
    card.cardKey = cardKey

    local function ApplyCollapseState()
        if card.collapsed then
            body:Hide()
            arrow:SetTexture(mediaPath .. "chevron_right")
            card:SetHeight(HEADER_HEIGHT)
        else
            body:Show()
            arrow:SetTexture(mediaPath .. "expand_more")
            card:SetHeight(HEADER_HEIGHT + bodyHeight)
        end
    end
    card.ApplyCollapseState = ApplyCollapseState

    header:RegisterForClicks("LeftButtonUp")
    header:SetScript("OnClick", function()
        card.collapsed = not card.collapsed
        GUI:GetCollapsedGroups()[cardKey] = card.collapsed or nil
        ApplyCollapseState()
        -- Trigger full re-render so the list reflows
        if DF.TextDesigner.RenderCardList then
            DF.TextDesigner.RenderCardList(card._GUI, card._page, card._tdDB, card._state)
        end
    end)

    ApplyCollapseState()

    -- ── UpdateMeta ───────────────────────────────────────────
    function card:UpdateMeta()
        local anchor = elem.anchor or "CENTER"
        local x = elem.offsetX or 0
        local y = elem.offsetY or 0
        local s = anchor .. " · " .. x .. "," .. y
        if elem.anchorTo and elem.anchorTo ~= "FRAME" then
            local targetID = tonumber(elem.anchorTo)
            if targetID and card._tdDB and card._tdDB.elements then
                for _, e in ipairs(card._tdDB.elements) do
                    if e.id == targetID then
                        local targetName
                        if e.label and e.label ~= "" then
                            targetName = e.label
                        else
                            local tct = FindContentType(e.contentType)
                            targetName = (tct and tct.label or e.contentType) .. " #" .. e.id
                        end
                        s = s .. " · → " .. targetName
                        break
                    end
                end
            end
        end
        meta:SetText(s)
    end
    card:UpdateMeta()

    -- ── RETURN ───────────────────────────────────────────────
    local totalCardH = card.collapsed and HEADER_HEIGHT or (HEADER_HEIGHT + bodyHeight)
    return card, totalCardH
end

-- ============================================================
-- CARD LIST RENDERER
-- Mirrors AuraDesigner's full-rebuild pattern (AuraDesigner/Options.lua:4882+
-- BuildEffectsTab): every render destroys all existing cards and rebuilds
-- them from scratch. No pool. This eliminates a class of "stale frame state
-- during reuse" bugs (card heights, dropdown options, etc.) at the cost of
-- a few CreateFrame calls per interaction — TD has at most ~20 elements and
-- rebuilds happen only on user-driven clicks, so cost is negligible.
-- ============================================================

local function RenderCardList(GUI, page, tdDB, state)
    -- Ensure listChild width matches the container — cards anchor TOPLEFT/TOPRIGHT
    -- to listChild, so if its width is 0/1 (e.g. before lazy sizing kicks in)
    -- they'll end up with negative width and render invisibly.
    -- Guard against transient 0: don't overwrite a good width with nothing.
    -- Nil-guard: during Phase 2.1 the Texts tab is still a stub, so
    -- state.listContainer / state.listChild may not exist yet.
    if state.listContainer and state.listChild then
        local cw = state.listContainer:GetWidth()
        if cw and cw > 1 then
            state.listChild:SetWidth(cw)
        end
    end

    -- Destroy ALL existing cards from any previous render. We can't actually
    -- free WoW frames (CreateFrame has no destructor), so we hide them,
    -- detach them from anchors, and nil out OnUpdate so any leftover
    -- per-frame closures don't keep running against this orphan card.
    if state.cardFrames then
        for _, card in pairs(state.cardFrames) do
            card:Hide()
            card:ClearAllPoints()
            card:SetScript("OnUpdate", nil)
        end
        wipe(state.cardFrames)
    else
        state.cardFrames = {}
    end

    -- Filter: only render non-group elements on Texts tab. Groups will get
    -- their own UI on the Groups tab (Task 3.x). Additionally honor the
    -- per-category filter chip selected on the Texts tab. When activeFilter is
    -- nil (e.g. RenderCardList called before BuildTextsTab has wired chips up)
    -- behave as if "_all" is selected so the pre-2.2 all-pass behavior holds.
    local activeFilter = state.activeFilter
    local elementsToShow = {}
    for _, elem in ipairs(tdDB.elements) do
        if elem.contentType ~= "group" then
            local ct = FindContentType(elem.contentType)
            local cat = ct and ct.category
            if activeFilter == nil or activeFilter == "_all" or activeFilter == cat then
                table.insert(elementsToShow, elem)
            end
        end
    end

    if #elementsToShow == 0 then
        if state.emptyMsg then
            -- Distinguish "filtered out" from "truly empty": if the user has any
            -- non-group elements at all but the active filter chip excludes them
            -- all, show a filter-aware hint instead of the generic empty-state.
            local hasAnyNonGroup = false
            for _, e in ipairs(tdDB.elements) do
                if e.contentType ~= "group" then hasAnyNonGroup = true; break end
            end
            if hasAnyNonGroup and activeFilter and activeFilter ~= "_all" then
                state.emptyMsg:SetText(L["No matching text elements. Try a different filter or click '+ Add Text Element'."])
            else
                state.emptyMsg:SetText(L["No text elements yet. Click '+ Add Text Element' to create one."])
            end
            state.emptyMsg:Show()
        end
        if state.emptyHint then state.emptyHint:Show() end
        if state.listChild then state.listChild:SetHeight(1) end
        return
    end

    if state.emptyMsg then state.emptyMsg:Hide() end
    if state.emptyHint then state.emptyHint:Hide() end

    -- Build fresh cards. CreateTextElementCard returns (card, totalCardH);
    -- we advance the y-cursor with that local rather than card:GetHeight()
    -- — same pattern as AD's BuildEffectsTab caller (AuraDesigner/Options.lua:5147).
    -- Skip building cards entirely if listChild isn't available yet (Phase 2.1
    -- stub state). Task 2.2 wires listChild up in BuildTextsTab.
    if not state.listChild then return end

    local y = 0
    local CARD_GAP = 5
    for _, elem in ipairs(elementsToShow) do
        local card, totalCardH = CreateTextElementCard(GUI, state.listChild, y, elem, tdDB, state, page)
        state.cardFrames[elem.id] = card
        y = y - totalCardH - CARD_GAP
    end
    state.listChild:SetHeight(math.max(1, -y + 4))
end

DF.TextDesigner.RenderCardList = RenderCardList  -- exposed for Task 6+

-- FullRebuildCards rebuilds the Texts tab card list and (if the Groups tab
-- has been built) the Groups tab card list too. Every render is a full
-- rebuild now that the pool is gone. Kept as a named export so existing
-- callers (delete button, picker onPick, label edit, group-item add/remove,
-- mode swap teardown logic, etc.) continue to work without churn.
local function FullRebuildCards(GUI, page, tdDB, state)
    RenderCardList(GUI, page, tdDB, state)
    if state.groupListChild and DF.TextDesigner.RenderGroupCardList then
        DF.TextDesigner.RenderGroupCardList(GUI, page, tdDB, state)
    end
end
DF.TextDesigner.FullRebuildCards = FullRebuildCards

-- The page state across builder invocations. Cached on the page frame.
local function GetState(page)
    page.dfTD = page.dfTD or {
        cardFrames = {},     -- pool of card frames keyed by elementID
        pickerFrame = nil,   -- the Add Element dropdown (created lazily)
    }
    return page.dfTD
end

-- ============================================================
-- TAB STRIP / TAB CONTENT STUBS
-- Phase 1.1 wires up the outer shell. The stubs below get fleshed out in
-- subsequent tasks:
--   BuildTabStrip   → Task 1.3 (tab strip + state.SelectTab)
--   BuildTextsTab   → Phase 2  (master toggle, list, cards, picker)
--   BuildGroupsTab  → Phase 3  (text-group definitions)
--   BuildGlobalTab  → Phase 4  (global text settings)
-- ============================================================

-- Three-tab strip (Texts / Text Groups / Global). Returns the strip frame so
-- callers can anchor content frames directly to it instead of going through
-- state.tabStrip. SelectTab is also exposed on state for external callers.
local function BuildTabStrip(GUI, parent, state, tdDB, page)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(28)
    strip:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    state.tabStrip = strip

    local tabDefs = {
        { id = "texts",  label = L["Texts"],       color = GUI.GetThemeColor() },
        { id = "groups", label = L["Text Groups"], color = {r = 0.91, g = 0.66, b = 0.25, a = 1} },  -- orange-ish (matches AD's layout-groups accent)
        { id = "global", label = L["Global"],      color = {r = 0.51, g = 0.86, b = 0.51, a = 1} },  -- green (matches AD's global accent)
    }

    local function SelectTab(tabID)
        state.activeTab = tabID
        for _, def in ipairs(tabDefs) do
            local btn = strip[def.id]
            if def.id == tabID then
                btn.text:SetTextColor(def.color.r, def.color.g, def.color.b, 1)
                btn.accent:Show()
            else
                btn.text:SetTextColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, 1)
                btn.accent:Hide()
            end
        end
        for id, contentFrame in pairs(state.tabContents or {}) do
            if id == tabID then contentFrame:Show() else contentFrame:Hide() end
        end
    end
    state.SelectTab = SelectTab

    local btnWidth = 100
    local btnGap = 4
    local x = 0
    for _, def in ipairs(tabDefs) do
        local btn = CreateFrame("Button", nil, strip)
        btn:SetSize(btnWidth, 28)
        btn:SetPoint("LEFT", strip, "LEFT", x, 0)
        local text = btn:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(text, 11, "OUTLINE")
        text:SetPoint("CENTER", btn, "CENTER", 0, 2)
        text:SetText(def.label)
        text:SetTextColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, 1)
        btn.text = text
        local accent = btn:CreateTexture(nil, "ARTWORK")
        accent:SetHeight(2)
        accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 8, 0)
        accent:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -8, 0)
        accent:SetColorTexture(def.color.r, def.color.g, def.color.b, 1)
        accent:Hide()
        btn.accent = accent
        btn:SetScript("OnClick", function() SelectTab(def.id) end)
        strip[def.id] = btn
        x = x + btnWidth + btnGap
    end

    SelectTab(state.activeTab or "texts")

    return strip
end

-- Texts tab content: "+ Add Text Element" hero CTA, filter chip row, and a
-- scrolling card list below. Mirrors AD's BuildEffectsTab structure
-- (AuraDesigner/Options.lua:4882+).
local function BuildTextsTab(GUI, parent, state, tdDB, page)
    -- ── "+ Add Text Element" hero CTA (theme-tinted) ──
    -- Raw BackdropTemplate Button so we get the same look as AD's hero CTA
    -- (theme-colored text + theme-tinted backdrop) without GUI:CreateButton's
    -- white text / default OnEnter handlers fighting us.
    local addBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    addBtn:SetHeight(32)
    addBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -10)
    addBtn:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    do
        local tc = GUI:GetThemeColor()
        ApplyBackdrop(addBtn,
            {r = tc.r * CTA_BG_RESTING,     g = tc.g * CTA_BG_RESTING,     b = tc.b * CTA_BG_RESTING,     a = 1},
            {r = tc.r * CTA_BORDER_RESTING, g = tc.g * CTA_BORDER_RESTING, b = tc.b * CTA_BORDER_RESTING, a = 1})

        local addBtnText = addBtn:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(addBtnText, 11, "OUTLINE")
        addBtnText:SetPoint("CENTER", 0, 0)
        addBtnText:SetText("+ " .. L["Add Text Element"])
        addBtnText:SetTextColor(tc.r, tc.g, tc.b)

        addBtn:SetScript("OnEnter", function(self)
            local c = GUI:GetThemeColor()
            self:SetBackdropColor(c.r * CTA_BG_HOVER, c.g * CTA_BG_HOVER, c.b * CTA_BG_HOVER, 1)
            self:SetBackdropBorderColor(c.r * CTA_BORDER_HOVER, c.g * CTA_BORDER_HOVER, c.b * CTA_BORDER_HOVER, 1)
            addBtnText:SetTextColor(1, 1, 1)
        end)
        addBtn:SetScript("OnLeave", function(self)
            local c = GUI:GetThemeColor()
            self:SetBackdropColor(c.r * CTA_BG_RESTING, c.g * CTA_BG_RESTING, c.b * CTA_BG_RESTING, 1)
            self:SetBackdropBorderColor(c.r * CTA_BORDER_RESTING, c.g * CTA_BORDER_RESTING, c.b * CTA_BORDER_RESTING, 1)
            addBtnText:SetTextColor(c.r, c.g, c.b)
        end)
    end
    state.addBtn = addBtn

    -- ── Filter chip row ──
    local chipRow = CreateFrame("Frame", nil, parent)
    chipRow:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -8)
    chipRow:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    chipRow:SetHeight(24)
    state.chipRow = chipRow

    state.activeFilter = state.activeFilter or "_all"

    local CHIP_H, CHIP_GAP, CHIP_ROW_GAP = 24, 4, 4
    local chips = {}

    local function MakeChip(label, key)
        local c = CreateFrame("Button", nil, chipRow, "BackdropTemplate")
        c:SetHeight(CHIP_H)
        ApplyBackdrop(c, C_PANEL, C_BORDER)
        local fs = c:CreateFontString(nil, "OVERLAY")
        GUI:SetSettingsFont(fs, 10, "OUTLINE")
        fs:SetPoint("CENTER")
        fs:SetText(label)
        c:SetWidth(fs:GetStringWidth() + 18)
        c.key = key
        c.fs = fs
        return c
    end

    local function ApplyChipState()
        local tc = GUI:GetThemeColor()
        for _, c in ipairs(chips) do
            if c.key == state.activeFilter then
                c:SetBackdropColor(tc.r, tc.g, tc.b, 0.20)
                c:SetBackdropBorderColor(tc.r, tc.g, tc.b, 0.50)
                c.fs:SetTextColor(1, 1, 1)
            else
                c:SetBackdropColor(C_PANEL.r, C_PANEL.g, C_PANEL.b, C_PANEL.a)
                c:SetBackdropBorderColor(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.5)
                c.fs:SetTextColor(0.75, 0.75, 0.75)
            end
        end
    end
    state.ApplyChipState = ApplyChipState

    local function LayoutChips()
        local maxW = chipRow:GetWidth()
        if maxW <= 0 then maxW = 260 end
        local cx, cy = 0, 0
        for _, c in ipairs(chips) do
            local bw = c:GetWidth()
            if cx > 0 and (cx + bw) > maxW then
                cx = 0
                cy = cy - (CHIP_H + CHIP_ROW_GAP)
            end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", chipRow, "TOPLEFT", cx, cy)
            cx = cx + bw + CHIP_GAP
        end
        chipRow:SetHeight(math.max(-cy + CHIP_H, CHIP_H))
    end

    local function AddChip(label, key)
        local c = MakeChip(label, key)
        chips[#chips+1] = c
        c:SetScript("OnClick", function(self)
            state.activeFilter = self.key
            ApplyChipState()
            if DF.TextDesigner.RenderCardList then
                DF.TextDesigner.RenderCardList(GUI, page, tdDB, state)
            end
        end)
        c:SetScript("OnEnter", function(self)
            if self.key ~= state.activeFilter then
                self:SetBackdropColor(C_HOVER.r, C_HOVER.g, C_HOVER.b, 1)
            end
        end)
        c:SetScript("OnLeave", function(self)
            if self.key ~= state.activeFilter then
                self:SetBackdropColor(C_PANEL.r, C_PANEL.g, C_PANEL.b, C_PANEL.a)
            end
        end)
    end

    AddChip(L["All"], "_all")
    for _, cat in ipairs(CONTENT_CATEGORIES) do
        if cat ~= "group" then  -- groups have their own tab
            AddChip(CONTENT_CATEGORY_LABELS[cat], cat)
        end
    end
    LayoutChips()
    chipRow:SetScript("OnSizeChanged", LayoutChips)
    ApplyChipState()

    -- ── Scrolling card list container ──
    local listContainer = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    listContainer:SetPoint("TOPLEFT", chipRow, "BOTTOMLEFT", 0, -6)
    listContainer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 8)
    if DF.GUI and DF.GUI.StyleScrollBar then DF.GUI.StyleScrollBar(listContainer) end
    listContainer:EnableMouseWheel(true)
    listContainer:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(current - delta * 20, self:GetVerticalScrollRange())))
    end)

    local listChild = CreateFrame("Frame", nil, listContainer)
    listChild:SetSize(listContainer:GetWidth() > 1 and listContainer:GetWidth() or 300, 1)
    listContainer:SetScrollChild(listChild)
    listContainer:HookScript("OnSizeChanged", function(self, w, h)
        if w and w > 1 then listChild:SetWidth(w) end
    end)

    state.listContainer = listContainer
    state.listChild = listChild
    state.cardFrames = state.cardFrames or {}

    -- ── Empty-state placeholder ──
    local emptyMsg = listChild:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(emptyMsg, 12, "")
    emptyMsg:SetPoint("CENTER", listContainer, "CENTER", 0, 0)
    emptyMsg:SetText(L["No text elements yet. Click '+ Add Text Element' to create one."])
    emptyMsg:SetTextColor(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.8)
    emptyMsg:SetJustifyH("CENTER")
    state.emptyMsg = emptyMsg

    -- ── Wire the Add button to the picker ──
    -- Reuse BuildPicker (the same one used by group-item adds). Caches the
    -- picker on state.addPicker so repeated clicks reuse the same frame.
    addBtn:SetScript("OnClick", function(self)
        if not BuildPicker then return end
        if not state.addPicker then
            state.addPicker = BuildPicker(GUI, parent, tdDB, function(typeKey)
                local ct = FindContentType(typeKey)
                if not ct then return end
                tdDB.nextElementID = tdDB.nextElementID or 1
                local id = tdDB.nextElementID
                tdDB.nextElementID = id + 1
                local newElem = {
                    id          = id,
                    contentType = typeKey,
                    enabled     = true,
                    label       = ComputeAutoLabel(tdDB, ct),
                }
                table.insert(tdDB.elements, newElem)

                -- Reset filter so the new card is visible regardless of which
                -- category chip is active.
                state.activeFilter = "_all"
                if state.ApplyChipState then state.ApplyChipState() end

                DF:Debug("TD", "Added element id=%d type=%s", id, typeKey)

                if DF.TextDesigner.FullRebuildCards then
                    DF.TextDesigner.FullRebuildCards(GUI, page, tdDB, state)
                end
            end, "group")  -- exclude "group" — groups have their own tab
        end
        local picker = state.addPicker
        if picker:IsShown() then
            picker:Hide()
        else
            picker:Open(self, "right")
        end
    end)

    -- Initial render — RenderCardList will hide emptyMsg if there are elements.
    if DF.TextDesigner.RenderCardList then
        DF.TextDesigner.RenderCardList(GUI, page, tdDB, state)
    end
end

-- ============================================================
-- GROUP CARD
-- A collapsible card representing one Text Group element (elem.contentType
-- == "group"). Structural clone of CreateTextElementCard but stripped down:
-- the group body shows ONLY the Content section (which already renders the
-- separator + item list + add-item picker). Groups are layout containers, so
-- there's no Appearance or Position section.
-- ============================================================

local function CreateGroupCard(GUI, parent, yPos, elem, tdDB, state, page)
    local HEADER_HEIGHT = 30

    -- Outer card: layout-only, no backdrop (matches CreateTextElementCard).
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, yPos)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, yPos)

    -- ── HEADER (group-themed accent) ─────────────────────────
    local header = CreateFrame("Button", nil, card, "BackdropTemplate")
    header:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    header:SetBackdropColor(C_ELEMENT.r, C_ELEMENT.g, C_ELEMENT.b, C_ELEMENT.a)
    header:SetBackdropBorderColor(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.5)

    header:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C_HOVER.r, C_HOVER.g, C_HOVER.b, C_HOVER.a)
    end)
    header:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C_ELEMENT.r, C_ELEMENT.g, C_ELEMENT.b, C_ELEMENT.a)
    end)
    card.header = header

    local mediaPath = "Interface\\AddOns\\DandersFrames\\Media\\Icons\\"

    -- Collapse arrow on the LEFT (tinted with the group category color).
    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("LEFT", header, "LEFT", 8, 0)
    local groupColor = CATEGORY_COLORS.group
    arrow:SetVertexColor(groupColor.r, groupColor.g, groupColor.b)
    card.collapseArrow = arrow

    -- Category-color chip
    local chip = header:CreateTexture(nil, "OVERLAY")
    chip:SetSize(4, 18)
    chip:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
    chip:SetColorTexture(groupColor.r, groupColor.g, groupColor.b, groupColor.a or 1)

    -- Title text
    local title = header:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(title, 11, "OUTLINE")
    title:SetPoint("LEFT", chip, "RIGHT", 8, 0)
    local displayName = (elem.label and elem.label ~= "" and elem.label) or L["Text Group"]
    title:SetText(displayName)
    title:SetTextColor(groupColor.r, groupColor.g, groupColor.b)
    card.title = title
    card.titleCatColor = groupColor

    -- Meta line (item count — populated after BuildContentSection runs below)
    local meta = header:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(meta, 9, "")
    meta:SetPoint("LEFT", title, "RIGHT", 8, 0)
    meta:SetTextColor(0.55, 0.6, 0.7)
    card.meta = meta

    -- ── ACTION ICONS (right side of header) ──────────────────
    -- Hand-drawn X delete (matches CreateTextElementCard).
    local ICON_SIZE = 18
    local ICON_GAP = 4

    local deleteBtn = CreateFrame("Button", nil, header)
    deleteBtn:SetSize(22, 22)
    deleteBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    local dxSize, dxThick = 12, 2
    local dline1 = deleteBtn:CreateTexture(nil, "OVERLAY")
    dline1:SetSize(dxSize, dxThick)
    dline1:SetPoint("CENTER")
    dline1:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
    dline1:SetRotation(math.rad(45))
    local dline2 = deleteBtn:CreateTexture(nil, "OVERLAY")
    dline2:SetSize(dxSize, dxThick)
    dline2:SetPoint("CENTER")
    dline2:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
    dline2:SetRotation(math.rad(-45))
    deleteBtn:SetScript("OnEnter", function()
        dline1:SetColorTexture(C_DESTRUCTIVE_HOVER.r, C_DESTRUCTIVE_HOVER.g, C_DESTRUCTIVE_HOVER.b, C_DESTRUCTIVE_HOVER.a)
        dline2:SetColorTexture(C_DESTRUCTIVE_HOVER.r, C_DESTRUCTIVE_HOVER.g, C_DESTRUCTIVE_HOVER.b, C_DESTRUCTIVE_HOVER.a)
    end)
    deleteBtn:SetScript("OnLeave", function()
        dline1:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
        dline2:SetColorTexture(C_DESTRUCTIVE.r, C_DESTRUCTIVE.g, C_DESTRUCTIVE.b, C_DESTRUCTIVE.a)
    end)
    card.deleteBtn = deleteBtn

    -- Eye icon (visibility toggle) — left of delete.
    local eyeBtn = CreateFrame("Button", nil, header)
    eyeBtn:SetSize(ICON_SIZE, ICON_SIZE)
    eyeBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -ICON_GAP, 0)
    local eyeIcon = eyeBtn:CreateTexture(nil, "OVERLAY")
    eyeIcon:SetAllPoints()
    local function updateEyeIcon()
        if elem.enabled then
            eyeIcon:SetTexture(mediaPath .. "visibility")
            eyeIcon:SetVertexColor(0.95, 0.95, 0.95)
        else
            eyeIcon:SetTexture(mediaPath .. "visibility_off")
            eyeIcon:SetVertexColor(0.45, 0.45, 0.45)
        end
    end
    updateEyeIcon()
    eyeBtn:SetScript("OnEnter", function() if elem.enabled then eyeIcon:SetVertexColor(1,1,1) end end)
    eyeBtn:SetScript("OnLeave", function() updateEyeIcon() end)
    eyeBtn:SetScript("OnClick", function()
        elem.enabled = not elem.enabled
        updateEyeIcon()
        DF:Debug("TD", "Group %d enabled=%s", elem.id, tostring(elem.enabled))
    end)
    card.eyeBtn = eyeBtn

    -- Click-through prevention on action icons
    for _, btn in ipairs({eyeBtn, deleteBtn}) do
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetFrameLevel(header:GetFrameLevel() + 5)
    end

    -- Delete OnClick (instant, no popup)
    deleteBtn:SetScript("OnClick", function()
        for i, e in ipairs(tdDB.elements) do
            if e.id == elem.id then
                table.remove(tdDB.elements, i)
                break
            end
        end
        if DF.TextDesigner.FullRebuildCards then
            DF.TextDesigner.FullRebuildCards(GUI, page, tdDB, state)
        end
        DF:Debug("TD", "Deleted group id=%d", elem.id)
    end)

    -- ── BODY ─────────────────────────────────────────────────
    local body = CreateFrame("Frame", nil, card, "BackdropTemplate")
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    body:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    body:SetBackdropColor(C_BODY_BG.r, C_BODY_BG.g, C_BODY_BG.b, C_BODY_BG.a)
    body:SetBackdropBorderColor(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.3)
    card.body = body

    -- Ensure default fields exist before BuildContentSection runs.
    elem.groupItems = elem.groupItems or {}
    elem.groupSeparator = elem.groupSeparator or " / "

    -- Reuse BuildContentSection's group branch — it handles the separator
    -- input, items list (with up/down/remove buttons), and Add Item picker.
    -- Groups don't get Appearance/Position sections.
    local yEnd = BuildContentSection(GUI, body, elem, tdDB, state, page, card, -10)
    local bodyHeight = math.max(1, -yEnd + 10)
    body:SetHeight(bodyHeight)

    -- Update meta line: show item count.
    meta:SetText(("(%d %s)"):format(#elem.groupItems, (#elem.groupItems == 1) and L["item"] or L["items"]))

    -- ── COLLAPSE STATE ───────────────────────────────────────
    -- Distinct key prefix from text elements so a group and a text element
    -- with the same numeric id never share collapse state.
    local cardKey = "td_group_" .. tostring(elem.id)
    local savedStates = GUI:GetCollapsedGroups()
    card.collapsed = savedStates[cardKey] == true
    card.cardKey = cardKey

    local function ApplyCollapseState()
        if card.collapsed then
            body:Hide()
            arrow:SetTexture(mediaPath .. "chevron_right")
            card:SetHeight(HEADER_HEIGHT)
        else
            body:Show()
            arrow:SetTexture(mediaPath .. "expand_more")
            card:SetHeight(HEADER_HEIGHT + bodyHeight)
        end
    end
    card.ApplyCollapseState = ApplyCollapseState

    header:RegisterForClicks("LeftButtonUp")
    header:SetScript("OnClick", function()
        card.collapsed = not card.collapsed
        GUI:GetCollapsedGroups()[cardKey] = card.collapsed or nil
        ApplyCollapseState()
        -- RenderGroupCardList is defined in Task 3.2. Resolving via
        -- DF.TextDesigner.* at click-time means the nil at function-define
        -- time is harmless; once the function lands, clicks pick it up.
        if DF.TextDesigner.RenderGroupCardList then
            DF.TextDesigner.RenderGroupCardList(GUI, page, tdDB, state)
        end
    end)

    ApplyCollapseState()

    local totalCardH = card.collapsed and HEADER_HEIGHT or (HEADER_HEIGHT + bodyHeight)
    return card, totalCardH
end

-- ============================================================
-- GROUP CARD LIST RENDERER
-- Modeled on RenderCardList. Filters tdDB.elements to entries with
-- contentType == "group" and renders each via CreateGroupCard into
-- state.groupListChild. Full-rebuild pattern: every render destroys
-- the previous card frames (Hide + ClearAllPoints) and creates fresh ones.
-- ============================================================
local function RenderGroupCardList(GUI, page, tdDB, state)
    if not state.groupListChild or not state.groupListContainer then return end

    state.groupListChild:SetWidth(state.groupListContainer:GetWidth())

    if state.groupCardFrames then
        for _, card in pairs(state.groupCardFrames) do
            card:Hide()
            card:ClearAllPoints()
            card:SetScript("OnUpdate", nil)
        end
        wipe(state.groupCardFrames)
    else
        state.groupCardFrames = {}
    end

    local groupsToShow = {}
    for _, elem in ipairs(tdDB.elements) do
        if elem.contentType == "group" then
            table.insert(groupsToShow, elem)
        end
    end

    if #groupsToShow == 0 then
        if state.groupEmptyMsg then state.groupEmptyMsg:Show() end
        state.groupListChild:SetHeight(1)
        return
    end

    if state.groupEmptyMsg then state.groupEmptyMsg:Hide() end

    local y = 0
    local CARD_GAP = 5
    for _, elem in ipairs(groupsToShow) do
        local card, totalCardH = CreateGroupCard(GUI, state.groupListChild, y, elem, tdDB, state, page)
        state.groupCardFrames[elem.id] = card
        y = y - totalCardH - CARD_GAP
    end
    state.groupListChild:SetHeight(math.max(1, -y + 4))
end
DF.TextDesigner.RenderGroupCardList = RenderGroupCardList

-- Text Groups tab: "+ Add Group" CTA top-left + scrolling list of group cards.
-- No picker: there's only one element type on this tab ("group"), so clicking
-- the button adds a new group element directly.
local function BuildGroupsTab(GUI, parent, state, tdDB, page)
    -- "+ Add Group" CTA top-left
    local addBtn = GUI:CreateButton(parent, "+ " .. L["Add Group"], 200, 32, function() end)
    addBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    do
        local tc = GUI:GetThemeColor()
        addBtn:SetBackdropColor(tc.r * CTA_BG_RESTING, tc.g * CTA_BG_RESTING, tc.b * CTA_BG_RESTING, 1)
        addBtn:SetBackdropBorderColor(tc.r * CTA_BORDER_RESTING, tc.g * CTA_BORDER_RESTING, tc.b * CTA_BORDER_RESTING, 1)
        addBtn:HookScript("OnEnter", function(self)
            local c = GUI:GetThemeColor()
            self:SetBackdropColor(c.r * CTA_BG_HOVER, c.g * CTA_BG_HOVER, c.b * CTA_BG_HOVER, 1)
            self:SetBackdropBorderColor(c.r * CTA_BORDER_HOVER, c.g * CTA_BORDER_HOVER, c.b * CTA_BORDER_HOVER, 1)
        end)
        addBtn:HookScript("OnLeave", function(self)
            local c = GUI:GetThemeColor()
            self:SetBackdropColor(c.r * CTA_BG_RESTING, c.g * CTA_BG_RESTING, c.b * CTA_BG_RESTING, 1)
            self:SetBackdropBorderColor(c.r * CTA_BORDER_RESTING, c.g * CTA_BORDER_RESTING, c.b * CTA_BORDER_RESTING, 1)
        end)
    end

    addBtn:SetScript("OnClick", function()
        -- Add a new group element directly (no picker — only one type)
        tdDB.nextElementID = tdDB.nextElementID or 1
        local id = tdDB.nextElementID
        tdDB.nextElementID = id + 1
        local groupCT = FindContentType("group")
        local elem = {
            id = id,
            contentType = "group",
            enabled = true,
            label = ComputeAutoLabel(tdDB, groupCT),
            groupItems = {},
            groupSeparator = " / ",
        }
        table.insert(tdDB.elements, elem)
        if DF.TextDesigner.FullRebuildCards then
            DF.TextDesigner.FullRebuildCards(GUI, page, tdDB, state)
        end
        DF:Debug("TD", "Added group id=%d", id)
    end)

    -- Scrolling list of group cards
    local listContainer = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    listContainer:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -10)
    listContainer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 8)
    if DF.GUI and DF.GUI.StyleScrollBar then DF.GUI.StyleScrollBar(listContainer) end
    listContainer:EnableMouseWheel(true)
    listContainer:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(current - delta * 20, self:GetVerticalScrollRange())))
    end)

    local listChild = CreateFrame("Frame", nil, listContainer)
    listChild:SetSize(listContainer:GetWidth() > 1 and listContainer:GetWidth() or 300, 1)
    listContainer:SetScrollChild(listChild)
    listContainer:HookScript("OnSizeChanged", function(self, w, h)
        if w and w > 1 then listChild:SetWidth(w) end
    end)

    state.groupAddBtn = addBtn
    state.groupListContainer = listContainer
    state.groupListChild = listChild
    state.groupCardFrames = state.groupCardFrames or {}

    -- Empty state
    local emptyMsg = listChild:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(emptyMsg, 12, "")
    emptyMsg:SetPoint("CENTER", listContainer, "CENTER", 0, 0)
    emptyMsg:SetText(L["No groups yet. Click '+ Add Group' to create one."])
    emptyMsg:SetTextColor(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.8)
    emptyMsg:SetJustifyH("CENTER")
    state.groupEmptyMsg = emptyMsg

    -- Initial render
    if DF.TextDesigner.RenderGroupCardList then
        DF.TextDesigner.RenderGroupCardList(GUI, page, tdDB, state)
    end
end

-- Stub — filled in Phase 4
local function BuildGlobalTab(GUI, parent, state, tdDB, page)
    local placeholder = parent:CreateFontString(nil, "OVERLAY")
    GUI:SetSettingsFont(placeholder, 12, "")
    placeholder:SetPoint("CENTER", parent, "CENTER", 0, 0)
    placeholder:SetText("(Global tab — filled in Phase 4)")
    placeholder:SetTextColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, 1)
end

-- ============================================================
-- BUILD ENTRYPOINT
-- ============================================================

function DF.BuildTextDesignerPage(GUI, page, db)
    DF.TextDesigner:EnsureDB(db)
    local tdDB = db.textDesigner
    local state = GetState(page)

    -- Override RefreshStates: TD doesn't use the Add() widget helper, so the
    -- default calculation would shrink page.child to ~40px tall, collapsing
    -- our list panel into an inside-out degenerate rect. Set page.child to
    -- the full page viewport instead. (Mirrors AuraDesigner/Options.lua:5849.)
    -- Installed every call (even when short-circuited) because RefreshStates
    -- may be invoked freshly on tab re-open.
    page.RefreshStates = function(self)
        if self.child then
            self.child:SetHeight(self:GetHeight())
            if GUI.contentFrame then
                self.child:SetWidth(GUI.contentFrame:GetWidth() - 30)
            end
        end
    end

    -- Detect mode change: if the page was previously built against a different
    -- db (party vs raid), tear down every cached widget so the rebuild below
    -- runs fresh against the new mode's data. Without this, switching modes
    -- via the existing mode buttons would leave the UI bound to whichever
    -- mode loaded first.
    if state.built and state.activeDB ~= db then
        if state.cardFrames then
            for _, card in pairs(state.cardFrames) do
                card:Hide()
                card:ClearAllPoints()
                card:SetScript("OnUpdate", nil)
            end
            wipe(state.cardFrames)
        end
        if state.copyBtnContainer  then state.copyBtnContainer:Hide();  state.copyBtnContainer:ClearAllPoints()  end
        if state.controlsBar       then state.controlsBar:Hide();       state.controlsBar:ClearAllPoints()       end
        if state.enableCheck       then state.enableCheck:Hide();       state.enableCheck:ClearAllPoints()       end
        if state.previewPanel      then state.previewPanel:Hide();      state.previewPanel:ClearAllPoints()      end
        if state.rightAnchorFrame  then state.rightAnchorFrame:Hide();  state.rightAnchorFrame:ClearAllPoints()  end
        if state.tabStrip          then state.tabStrip:Hide();          state.tabStrip:ClearAllPoints()          end
        -- Texts tab Phase 2.2 fields. The chipRow / emptyMsg / listContainer /
        -- listChild are children of state.tabContents.texts so they'll go down
        -- with their parent below, but we explicitly Hide+ClearAllPoints them
        -- here so the state references can be nil'd without leaks. addPicker
        -- is parented to UIParent (see BuildPicker), so it needs its own
        -- teardown — otherwise it would survive the mode swap.
        if state.addBtn        then state.addBtn:Hide();        state.addBtn:ClearAllPoints()        end
        if state.chipRow       then state.chipRow:Hide();       state.chipRow:ClearAllPoints()       end
        if state.listContainer then state.listContainer:Hide(); state.listContainer:ClearAllPoints() end
        if state.listChild     then state.listChild:Hide();     state.listChild:ClearAllPoints()     end
        if state.emptyMsg      then state.emptyMsg:Hide();      state.emptyMsg:ClearAllPoints()      end
        if state.addPicker     then state.addPicker:Hide();     state.addPicker:ClearAllPoints()     end
        -- Groups tab (Phase 3.2) fields. groupCardFrames is iterated like
        -- cardFrames above; the remaining frames are children of
        -- state.tabContents.groups so they go down with their parent below,
        -- but we explicitly Hide+ClearAllPoints them so state refs can be nil'd.
        if state.groupCardFrames then
            for _, card in pairs(state.groupCardFrames) do
                card:Hide()
                card:ClearAllPoints()
                card:SetScript("OnUpdate", nil)
            end
            wipe(state.groupCardFrames)
        end
        if state.groupAddBtn        then state.groupAddBtn:Hide();        state.groupAddBtn:ClearAllPoints()        end
        if state.groupListContainer then state.groupListContainer:Hide(); state.groupListContainer:ClearAllPoints() end
        if state.groupListChild     then state.groupListChild:Hide();     state.groupListChild:ClearAllPoints()     end
        if state.groupEmptyMsg      then state.groupEmptyMsg:Hide();      state.groupEmptyMsg:ClearAllPoints()      end
        if state.tabContents       then
            for _, frame in pairs(state.tabContents) do
                frame:Hide()
                frame:ClearAllPoints()
            end
            wipe(state.tabContents)
        end
        state.copyBtnContainer  = nil
        state.controlsBar       = nil
        state.enableCheck       = nil
        state.previewPanel      = nil
        state.rightAnchorFrame  = nil
        state.tabStrip          = nil
        state.SelectTab         = nil
        state.tabContents       = nil
        state.activeTab         = nil
        state.addBtn            = nil
        state.chipRow           = nil
        state.ApplyChipState    = nil
        state.activeFilter      = nil
        state.listContainer     = nil
        state.listChild         = nil
        state.emptyMsg          = nil
        state.addPicker         = nil
        state.groupAddBtn        = nil
        state.groupListContainer = nil
        state.groupListChild     = nil
        state.groupEmptyMsg      = nil
        state.groupCardFrames    = nil
        state.built = false
    end

    if state.built then return end
    state.built = true
    state.activeDB = db

    -- ── TOP BANNER (full width) ───────────────────────────────
    -- Copy / Sync trio top-right. omitReset = true matches the prior decision
    -- to hide the Reset Page button until we have a dedicated reset flow.
    local copyBtnContainer = GUI.CreateCopyButton(
        page.child,
        {"textDesigner"},
        L["Text Designer"],
        "text_designer",
        true
    )
    copyBtnContainer:SetPoint("TOPRIGHT", page.child, "TOPRIGHT", -10, -10)
    state.copyBtnContainer = copyBtnContainer

    -- Full-width controls bar below the copy trio. Holds the master toggle
    -- (and future top-banner controls). The "+ Add Text Element" button now
    -- belongs to the Texts tab (Phase 2), not this bar.
    local controlsBar = CreateFrame("Frame", nil, page.child)
    controlsBar:SetHeight(32)
    controlsBar:SetPoint("TOPLEFT", page.child, "TOPLEFT", 10, -42)
    controlsBar:SetPoint("TOPRIGHT", page.child, "TOPRIGHT", -10, -42)
    state.controlsBar = controlsBar

    -- Master "Enable Text Designer" toggle, top-left of the banner.
    local enableCheck = GUI:CreateCheckbox(
        controlsBar,
        L["Enable Text Designer"],
        tdDB,
        "enabled",
        function() DF:Debug("TD", "Enable Text Designer = %s", tostring(tdDB.enabled)) end
    )
    enableCheck:SetPoint("LEFT", controlsBar, "LEFT", 0, 0)
    state.enableCheck = enableCheck

    -- ── PREVIEW PANEL (left half, below banner) ────────────────
    -- Visual clone of AD's frame preview. The mockFrame mirrors the current
    -- frame settings (width / height / power) so the chrome looks proportional;
    -- fill values are static placeholders.
    local previewPanel = CreateFrame("Frame", nil, page.child, "BackdropTemplate")
    ApplyBackdrop(previewPanel, C_PANEL, C_BORDER)
    previewPanel:SetPoint("TOPLEFT", controlsBar, "BOTTOMLEFT", 0, -10)
    previewPanel:SetPoint("BOTTOM", page.child, "BOTTOM", 0, 10)
    previewPanel:SetPoint("RIGHT", page.child, "CENTER", -2, 0)
    state.previewPanel = previewPanel

    -- "Frame Preview" label
    local previewLabel = previewPanel:CreateFontString(nil, "OVERLAY", "DFFontHighlightSmall")
    previewLabel:SetPoint("TOPLEFT", 8, -4)
    previewLabel:SetText(L["FRAME PREVIEW"] or "FRAME PREVIEW")
    previewLabel:SetTextColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b)

    -- Mock unit frame (centred in panel) — visual clone of AD's mockFrame.
    do
        local mode = (GUI and GUI.SelectedMode) or "party"
        local frameDB = (DF.GetDB and DF:GetDB(mode)) or DF.PartyDefaults or {}
        local FRAME_W = frameDB.frameWidth or 125
        local FRAME_H = frameDB.frameHeight or 64
        local POWER_H = frameDB.powerBarHeight or 4
        local showPower = frameDB.showPowerBar

        local mockFrame = CreateFrame("Frame", nil, previewPanel, "BackdropTemplate")
        mockFrame:SetSize(FRAME_W, FRAME_H)
        mockFrame:SetPoint("CENTER", previewPanel, "CENTER", 0, -4)
        ApplyBackdrop(mockFrame, {r = 0.07, g = 0.07, b = 0.07, a = 1}, {r = 0.27, g = 0.27, b = 0.27, a = 1})
        previewPanel.mockFrame = mockFrame

        local healthTexPath = frameDB.healthTexture or "Interface\\Buttons\\WHITE8x8"

        -- Health bar background
        local healthBg = mockFrame:CreateTexture(nil, "BACKGROUND")
        healthBg:SetPoint("TOPLEFT", 1, -1)
        if showPower then
            healthBg:SetPoint("BOTTOMRIGHT", mockFrame, "BOTTOMRIGHT", -1, POWER_H + 1)
        else
            healthBg:SetPoint("BOTTOMRIGHT", mockFrame, "BOTTOMRIGHT", -1, 1)
        end
        healthBg:SetColorTexture(0, 0, 0, 0.4)

        -- Health bar fill (72% health, placeholder)
        local healthFill = mockFrame:CreateTexture(nil, "ARTWORK")
        healthFill:SetPoint("TOPLEFT", 1, -1)
        if showPower then
            healthFill:SetPoint("BOTTOMLEFT", mockFrame, "BOTTOMLEFT", 1, POWER_H + 1)
        else
            healthFill:SetPoint("BOTTOMLEFT", mockFrame, "BOTTOMLEFT", 1, 1)
        end
        healthFill:SetWidth(FRAME_W * 0.72)
        healthFill:SetTexture(healthTexPath)
        healthFill:SetVertexColor(0.18, 0.80, 0.44, 0.85)

        -- Missing health region
        local missingHealth = mockFrame:CreateTexture(nil, "ARTWORK")
        missingHealth:SetPoint("TOPRIGHT", mockFrame, "TOPRIGHT", -1, -1)
        if showPower then
            missingHealth:SetPoint("BOTTOMRIGHT", mockFrame, "BOTTOMRIGHT", -1, POWER_H + 1)
        else
            missingHealth:SetPoint("BOTTOMRIGHT", mockFrame, "BOTTOMRIGHT", -1, 1)
        end
        missingHealth:SetWidth(FRAME_W * 0.28)
        missingHealth:SetColorTexture(0, 0, 0, 0.4)

        -- Power bar (only if enabled in current frame settings)
        if showPower then
            local powerBg = mockFrame:CreateTexture(nil, "ARTWORK")
            powerBg:SetPoint("BOTTOMLEFT", 1, 1)
            powerBg:SetPoint("BOTTOMRIGHT", mockFrame, "BOTTOMRIGHT", -1, 0)
            powerBg:SetHeight(POWER_H)
            powerBg:SetColorTexture(0.07, 0.07, 0.07, 1)

            local powerFill = mockFrame:CreateTexture(nil, "ARTWORK", nil, 1)
            powerFill:SetPoint("BOTTOMLEFT", 1, 1)
            powerFill:SetHeight(POWER_H)
            powerFill:SetWidth(FRAME_W * 0.85)
            powerFill:SetColorTexture(0.27, 0.53, 1, 0.9)

            local powerBorder = mockFrame:CreateTexture(nil, "ARTWORK", nil, 2)
            powerBorder:SetPoint("BOTTOMLEFT", mockFrame, "BOTTOMLEFT", 1, POWER_H)
            powerBorder:SetPoint("BOTTOMRIGHT", mockFrame, "BOTTOMRIGHT", -1, POWER_H)
            powerBorder:SetHeight(1)
            powerBorder:SetColorTexture(0.2, 0.2, 0.2, 1)
        end

        -- Placeholder name + HP text (static — does NOT respect TD elements)
        local nameText = mockFrame:CreateFontString(nil, "OVERLAY")
        local nameFontPath = (DF.GetFontPath and DF:GetFontPath(frameDB.nameFont)) or "Fonts\\FRIZQT__.TTF"
        nameText:SetFont(nameFontPath, frameDB.nameFontSize or 11, "OUTLINE")
        nameText:SetPoint("TOP", mockFrame, "TOP", 0, -10)
        nameText:SetText("Danders")
        nameText:SetTextColor(0.18, 0.80, 0.44, 1)

        local hpText = mockFrame:CreateFontString(nil, "OVERLAY")
        local healthFontPath = (DF.GetFontPath and DF:GetFontPath(frameDB.healthFont)) or "Fonts\\FRIZQT__.TTF"
        hpText:SetFont(healthFontPath, frameDB.healthFontSize or 10, "OUTLINE")
        hpText:SetPoint("CENTER", mockFrame, "CENTER", 0, 4)
        hpText:SetText("72%")
        hpText:SetTextColor(0.87, 0.87, 0.87, 1)

        -- Static anchor dots — 9 positions, decorative only (no drag handlers).
        local ANCHOR_POSITIONS = {
            TOPLEFT     = "TOPLEFT",
            TOP         = "TOP",
            TOPRIGHT    = "TOPRIGHT",
            LEFT        = "LEFT",
            CENTER      = "CENTER",
            RIGHT       = "RIGHT",
            BOTTOMLEFT  = "BOTTOMLEFT",
            BOTTOM      = "BOTTOM",
            BOTTOMRIGHT = "BOTTOMRIGHT",
        }
        for _, anchorName in pairs(ANCHOR_POSITIONS) do
            local dot = mockFrame:CreateTexture(nil, "OVERLAY")
            dot:SetSize(6, 6)
            dot:SetPoint("CENTER", mockFrame, anchorName, 0, 0)
            dot:SetColorTexture(0.45, 0.45, 0.95, 0.3)
        end
    end

    -- Placeholder note so users know this panel is purely cosmetic for now.
    local previewNote = previewPanel:CreateFontString(nil, "OVERLAY", "DFFontHighlightSmall")
    previewNote:SetPoint("BOTTOM", previewPanel, "BOTTOM", 0, 10)
    previewNote:SetText("Preview placeholder (visual mockup)")
    previewNote:SetTextColor(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, 0.8)

    -- ── RIGHT-SIDE CONTAINER ───────────────────────────────────
    -- Invisible host for the tab strip + per-tab content frames.
    local rightAnchorFrame = CreateFrame("Frame", nil, page.child)
    rightAnchorFrame:SetPoint("TOPLEFT", previewPanel, "TOPRIGHT", 6, 0)
    rightAnchorFrame:SetPoint("BOTTOMRIGHT", page.child, "BOTTOMRIGHT", 0, 0)
    state.rightAnchorFrame = rightAnchorFrame

    -- ── TAB STRIP ──────────────────────────────────────────────
    local tabStrip = BuildTabStrip(GUI, rightAnchorFrame, state, tdDB, page)

    -- ── TAB CONTENT FRAMES (one per tab) ───────────────────────
    state.tabContents = {}
    local function CreateTabContentFrame()
        local f = CreateFrame("Frame", nil, rightAnchorFrame)
        f:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -4)
        f:SetPoint("BOTTOMRIGHT", rightAnchorFrame, "BOTTOMRIGHT", 0, 0)
        f:Hide()
        return f
    end
    state.tabContents.texts  = CreateTabContentFrame()
    state.tabContents.groups = CreateTabContentFrame()
    state.tabContents.global = CreateTabContentFrame()

    state.activeTab = state.activeTab or "texts"

    BuildTextsTab(GUI, state.tabContents.texts, state, tdDB, page)
    BuildGroupsTab(GUI, state.tabContents.groups, state, tdDB, page)
    BuildGlobalTab(GUI, state.tabContents.global, state, tdDB, page)

    -- Show only the active tab
    state.tabContents[state.activeTab]:Show()
end
