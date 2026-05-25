local addonName, DF = ...

-- ============================================================
-- TEXT DESIGNER — PREVIEW
-- Renders TD text elements as FontStrings onto the existing
-- static demo mock frame in Options.lua's preview panel.
-- The mock frame itself is owned by Options.lua (not this module).
-- ============================================================

DF.TextDesigner = DF.TextDesigner or {}
local Preview = {}
DF.TextDesigner.Preview = Preview

local activeMockFrame = nil
local activeTdDB = nil

-- Called from TextDesigner/Options.lua's BuildTextDesignerPage to
-- bind this module to the current mock frame + tdDB. Mode switching
-- calls this again with a new mock frame; we tear down the old
-- FontStrings before re-binding.
function Preview:Init(mockFrame, tdDB)
    if activeMockFrame and activeMockFrame ~= mockFrame then
        if DF.TextDesigner.Render then
            DF.TextDesigner.Render:Teardown(activeMockFrame)
        end
    end
    activeMockFrame = mockFrame
    activeTdDB = tdDB
    self:RefreshAll()
end

-- Refreshes all TD FontStrings on the bound mock frame using
-- synthetic mock data. Called on settings changes (FullRebuildCards,
-- eye-icon toggle, master toggle).
function Preview:RefreshAll()
    DF:Debug("TD", "Preview:RefreshAll called, mockFrame=%s tdDB=%s",
        tostring(activeMockFrame), tostring(activeTdDB))
    if not activeMockFrame or not activeTdDB then return end
    local Render = DF.TextDesigner.Render
    local DataSource = DF.TextDesigner.DataSource
    if not Render or not DataSource then return end
    local source = DataSource.Mock()
    -- isPreview=true so the master "Enable Text Designer" toggle does NOT
    -- hide preview text — the preview is for "see what your text will look
    -- like when enabled".
    Render:UpdateFrame(activeMockFrame, activeTdDB, source, "all", true)
end

-- Returns the currently bound mock frame.
function Preview:GetFrame()
    return activeMockFrame
end
