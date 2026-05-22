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

    -- Add Element button (functionality lands in Task 4)
    local addBtn = GUI:CreateButton(controlsBar, "+ " .. L["Add Text Element"], 160, 22, function()
        DF:Debug("TD", "Add Element clicked (picker lands in Task 4)")
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
