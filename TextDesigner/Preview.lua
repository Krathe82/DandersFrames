local addonName, DF = ...

-- ============================================================
-- TEXT DESIGNER — PREVIEW
-- Chrome-only mock unit frame for the settings preview panel.
-- Drawn from the user's actual db.party settings (textures,
-- colors, gradient direction, border style) so the preview
-- reflects what their real frames will look like.
-- TD text elements layer on top via Render.
-- ============================================================

DF.TextDesigner = DF.TextDesigner or {}
local Preview = {}
DF.TextDesigner.Preview = Preview

-- Preview frame dimensions. Fixed since the preview panel is fixed
-- size; if the user's actual frames are larger/smaller, this preview
-- shows a relative approximation.
local PREVIEW_W, PREVIEW_H = 180, 60
local HEALTH_BAR_H = 38  -- portion of frame height
local POWER_BAR_H = 12

-- The active preview frame instance (singleton — there's only one
-- preview mock at a time).
local activePreviewFrame = nil
local activeState = nil
local activeTdDB = nil

-- ============================================================
-- TEXTURE / COLOR HELPERS
-- ============================================================

local function lsmTexture(key, fallback)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and key then
        local path = LSM:Fetch("statusbar", key, true)
        if path then return path end
    end
    return fallback or "Interface\\TargetingFrame\\UI-StatusBar"
end

-- Reads the relevant settings from db.party (or db.raid) for chrome rendering.
local function resolveChromeSettings(db)
    db = db or {}
    return {
        healthBarTexture = lsmTexture(db.healthBarTexture, nil),
        healthBarColor   = db.healthBarColor or {r=0.18, g=0.80, b=0.44, a=1},
        powerBarTexture  = lsmTexture(db.powerBarTexture, nil),
        showPowerBar     = db.showPowerBar ~= false,  -- default true
        backgroundColor  = db.backgroundColor or {r=0.10, g=0.10, b=0.10, a=1},
        borderColor      = db.borderColor or {r=0.30, g=0.30, b=0.30, a=1},
    }
end

-- ============================================================
-- BUILD THE MOCK FRAME
-- Called once when the TD settings page is built.
-- ============================================================

function Preview:Build(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(PREVIEW_W, PREVIEW_H)
    frame:SetPoint("CENTER", parent, "CENTER", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    -- Background + border are reapplied on RefreshAll from current settings
    frame:SetBackdropColor(0.10, 0.10, 0.10, 1)
    frame:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)

    -- Health bar (StatusBar)
    local hb = CreateFrame("StatusBar", nil, frame)
    hb:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    hb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    hb:SetHeight(HEALTH_BAR_H)
    hb:SetMinMaxValues(0, 100)
    hb:SetValue(61)  -- mock HP%
    frame._healthBar = hb

    -- Power bar (StatusBar) — only shown if settings enable it
    local pb = CreateFrame("StatusBar", nil, frame)
    pb:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
    pb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    pb:SetHeight(POWER_BAR_H)
    pb:SetMinMaxValues(0, 100)
    pb:SetValue(55)  -- mock power%
    frame._powerBar = pb

    -- The frame is the parent for TD FontStrings; Render hangs them off it.
    -- Make it usable as a "unit frame" for the renderer by setting a sentinel
    -- field that LiveSource won't try to use.
    frame._isPreviewMockFrame = true

    activePreviewFrame = frame
    return frame
end

-- ============================================================
-- APPLY CURRENT CHROME (from db) TO THE PREVIEW FRAME
-- ============================================================

local function applyChrome(frame, db)
    local chrome = resolveChromeSettings(db)
    -- Background
    frame:SetBackdropColor(chrome.backgroundColor.r, chrome.backgroundColor.g, chrome.backgroundColor.b, chrome.backgroundColor.a or 1)
    frame:SetBackdropBorderColor(chrome.borderColor.r, chrome.borderColor.g, chrome.borderColor.b, chrome.borderColor.a or 1)
    -- Health bar
    if chrome.healthBarTexture then frame._healthBar:SetStatusBarTexture(chrome.healthBarTexture) end
    frame._healthBar:SetStatusBarColor(chrome.healthBarColor.r, chrome.healthBarColor.g, chrome.healthBarColor.b, chrome.healthBarColor.a or 1)
    -- Power bar
    if chrome.showPowerBar then
        if chrome.powerBarTexture then frame._powerBar:SetStatusBarTexture(chrome.powerBarTexture) end
        -- Power color: derived from mock token "MANA"
        local powerColor = DF.GetPowerColor and DF:GetPowerColor("MANA", 0) or {r=0.27, g=0.53, b=1, a=1}
        frame._powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b, powerColor.a or 1)
        frame._powerBar:Show()
    else
        frame._powerBar:Hide()
    end
end

-- ============================================================
-- REFRESH ALL — re-runs chrome + Render against the mock source
-- ============================================================

function Preview:RefreshAll()
    if not activePreviewFrame then return end
    if not activeTdDB then return end
    -- Resolve the current mode's full db for chrome
    local mode = (DF.db and DF.db.party and activeTdDB == DF.db.party.textDesigner) and "party" or "raid"
    local frameDb = DF.db and DF.db[mode]
    applyChrome(activePreviewFrame, frameDb)
    local Render = DF.TextDesigner.Render
    local source = DF.TextDesigner.DataSource.Mock()
    Render:UpdateFrame(activePreviewFrame, activeTdDB, source, "all")
end

-- Called from TextDesigner/Options.lua's BuildTextDesignerPage to set up
-- the preview frame + remember the active tdDB.
function Preview:Init(parent, tdDB)
    if activePreviewFrame and activePreviewFrame:GetParent() ~= parent then
        -- Mode switch — tear down the previous preview and re-create
        DF.TextDesigner.Render:Teardown(activePreviewFrame)
        activePreviewFrame:Hide()
        activePreviewFrame:ClearAllPoints()
        activePreviewFrame = nil
    end
    if not activePreviewFrame then
        self:Build(parent)
    end
    activeTdDB = tdDB
    self:RefreshAll()
end

function Preview:GetFrame()
    return activePreviewFrame
end
