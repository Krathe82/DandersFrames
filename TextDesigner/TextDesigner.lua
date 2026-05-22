local addonName, DF = ...

-- ============================================================
-- TEXT DESIGNER - MODULE ENTRY
-- Alpha-only feature for designing arbitrary text elements on
-- unit frames. Phase 1: UI scaffold only (no rendering).
-- See docs/superpowers/specs/2026-05-22-text-designer-phase1-design.md
-- ============================================================

-- Release-channel gate: don't even register globals on release builds.
-- DF.RELEASE_CHANNEL is set in Changelog.lua by CI.
if DF.RELEASE_CHANNEL == "release" then return end

local pairs, ipairs = pairs, ipairs

DF.TextDesigner = DF.TextDesigner or {}

-- ============================================================
-- DB STUB INITIALIZATION
-- Phase 1 only needs enough schema to track editor state.
-- Full per-element schema firms up in Phase 2 when rendering wires up.
-- ============================================================

function DF.TextDesigner:EnsureDB(db)
    if not db then return end
    db.textDesigner = db.textDesigner or {}
    db.textDesigner.enabled = db.textDesigner.enabled
    if db.textDesigner.enabled == nil then db.textDesigner.enabled = false end
    db.textDesigner.nextElementID = db.textDesigner.nextElementID or 1
    db.textDesigner.elements = db.textDesigner.elements or {}
    return db.textDesigner
end

DF:Debug("TD", "TextDesigner module loaded (channel=%s)", tostring(DF.RELEASE_CHANNEL))
