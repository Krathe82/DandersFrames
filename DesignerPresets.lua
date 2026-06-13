local addonName, DF = ...

-- ============================================================
-- DESIGNER PRESETS
-- Named, profile-level libraries of Aura Designer (AD) and Text
-- Designer (TD) configurations. Consumers (party frames, raid
-- frames, and later each pinned set) store only a preset *name*;
-- the canonical config table lives once in the library.
--
-- Storage (profile root, sibling of db.party / db.raid):
--   DF.db.auraDesignerPresets  = { ["Default"]={…}, ["Party"]={…}, ["Raid"]={…}, … }
--   DF.db.textDesignerPresets  = { ["Default"]={…}, ["Party"]={…}, ["Raid"]={…}, … }
--
-- Consumer references (per mode db):
--   DF.db.party.auraDesignerPreset = "Party"
--   DF.db.raid.auraDesignerPreset  = "Raid"   (+ textDesignerPreset)
--
-- Storing the NAME (a plain string), never a duplicated table, avoids
-- the SavedVariables "shared table reference splits into two copies on
-- reload" trap — there is one canonical table per preset.
-- ============================================================

local pairs, ipairs = pairs, ipairs

DF.DEFAULT_PRESET = "Default"   -- non-deletable ultimate fallback

-- ============================================================
-- FACTORIES — fresh, default-shaped designer configs
-- ============================================================

-- A clean Aura Designer config: a deep copy of the Party defaults
-- template (enabled = false, empty per-spec auras). DeepCopy keeps us
-- in lockstep with Config.lua without duplicating the defaults table.
function DF:NewAuraDesignerConfig()
    local base = DF.PartyDefaults and DF.PartyDefaults.auraDesigner
    local cfg
    if base then
        cfg = DF:DeepCopy(base)
    else
        cfg = { enabled = false, spec = "auto", previewScale = 1.0, soundEnabled = true,
                defaults = {}, auras = {}, layoutGroups = {}, nextLayoutGroupID = 1 }
    end
    -- Force a pristine, disabled config regardless of what the template carried.
    cfg.enabled = false
    cfg.auras = {}
    cfg.layoutGroups = {}
    cfg.nextLayoutGroupID = 1
    return cfg
end

-- A clean Text Designer config. TD has no Config.lua template — its
-- shape is owned by DF.TextDesigner:EnsureDB, so seed through that.
function DF:NewTextDesignerConfig()
    if DF.TextDesigner and DF.TextDesigner.EnsureDB then
        return DF.TextDesigner:EnsureDB({})
    end
    return { enabled = false, hideLegacyText = false, nextElementID = 1,
             elements = {}, previewScale = 1.0, globalDefaults = {} }
end

-- ============================================================
-- LIBRARY ACCESSORS
-- Lazily create the library + the non-deletable "Default" entry.
-- Return nil only before the profile DB exists (very early boot).
-- ============================================================

function DF:GetAuraDesignerPresets()
    if not DF.db then return nil end
    local lib = DF.db.auraDesignerPresets
    if not lib then
        lib = {}
        DF.db.auraDesignerPresets = lib
    end
    if not lib[DF.DEFAULT_PRESET] then
        lib[DF.DEFAULT_PRESET] = DF:NewAuraDesignerConfig()
    end
    return lib
end

function DF:GetTextDesignerPresets()
    if not DF.db then return nil end
    local lib = DF.db.textDesignerPresets
    if not lib then
        lib = {}
        DF.db.textDesignerPresets = lib
    end
    if not lib[DF.DEFAULT_PRESET] then
        lib[DF.DEFAULT_PRESET] = DF:NewTextDesignerConfig()
    end
    return lib
end

-- The default preset name a given mode maps to when it has no explicit
-- assignment yet (party → "Party", raid → "Raid").
local function DefaultPresetNameForMode(mode)
    return mode == "raid" and "Raid" or "Party"
end
DF.DefaultPresetNameForMode = DefaultPresetNameForMode

-- ============================================================
-- RESOLVERS — frame → the designer config it should render with
-- ============================================================

-- Determine which config mode a frame belongs to. Pinned frames will
-- later resolve to their Based-on mode; for now that is handled by the
-- same isRaidFrame flag the rest of the frame system uses.
local function FrameMode(frame)
    if frame and DF.IsRaidFrame and DF:IsRaidFrame(frame) then
        return "raid"
    end
    return "party"
end

local function ResolvePreset(frame, lib, presetKey)
    if not lib then return nil end
    -- Explicit per-frame override stamp (used by the editor preview and,
    -- later, pinned sets) takes precedence over mode resolution.
    local override = frame and frame[presetKey == "auraDesignerPreset"
        and "dfAuraPresetOverride" or "dfTextPresetOverride"]
    if override and lib[override] then return lib[override] end

    local mode = FrameMode(frame)
    local modeDB = DF:GetDB(mode)
    local name = (modeDB and modeDB[presetKey]) or DefaultPresetNameForMode(mode)
    return lib[name] or lib[DF.DEFAULT_PRESET]
end

function DF:ResolveAuraDesigner(frame)
    local lib = DF:GetAuraDesignerPresets()
    if not lib then
        -- Pre-migration / very early: fall back to the legacy inline config.
        local db = DF.GetFrameDB and DF:GetFrameDB(frame)
        return db and db.auraDesigner or nil
    end
    return ResolvePreset(frame, lib, "auraDesignerPreset")
end

function DF:ResolveTextDesigner(frame)
    local lib = DF:GetTextDesignerPresets()
    if not lib then
        local db = DF.GetFrameDB and DF:GetFrameDB(frame)
        return db and db.textDesigner or nil
    end
    return ResolvePreset(frame, lib, "textDesignerPreset")
end

-- Resolve the preset a given MODE (not a frame) edits/uses. Used by the
-- editors, whose page is mode-tabbed: the preset a mode edits is always
-- the preset it uses, so the live frames stay in sync with the editor.
function DF:GetModeAuraDesigner(mode)
    local lib = DF:GetAuraDesignerPresets()
    if not lib then return nil end
    local modeDB = DF:GetDB(mode)
    local name = (modeDB and modeDB.auraDesignerPreset) or DefaultPresetNameForMode(mode)
    return lib[name] or lib[DF.DEFAULT_PRESET], (name or DF.DEFAULT_PRESET)
end

function DF:GetModeTextDesigner(mode)
    local lib = DF:GetTextDesignerPresets()
    if not lib then return nil end
    local modeDB = DF:GetDB(mode)
    local name = (modeDB and modeDB.textDesignerPreset) or DefaultPresetNameForMode(mode)
    return lib[name] or lib[DF.DEFAULT_PRESET], (name or DF.DEFAULT_PRESET)
end

-- ============================================================
-- MIGRATION (lossless, all profiles)
-- Moves every inline auraDesigner / textDesigner config into the preset
-- library and points its owner at the preset by NAME:
--   * db.party / db.raid           → "Party" / "Raid" presets
--   * each raid auto-layout's       → a uniquely-named preset, with the
--     overrides.<designer> table       layout's override switched to the
--                                       string key <designer>Preset
-- The inline table is MOVED by reference (not copied) then cleared, so
-- there is exactly one canonical owner — no SavedVariables shared-ref
-- duplication, and the old whole-table-override path goes dormant (the
-- per-layout override is now a plain string the generic overlay handles).
-- Idempotent: guarded so re-runs on already-migrated profiles are no-ops.
-- ============================================================

-- Pick a library-unique preset name from a base label.
local function UniquePresetName(lib, base)
    base = (type(base) == "string" and base ~= "" and base) or "Layout"
    if not lib[base] then return base end
    local i = 2
    while lib[base .. " " .. i] do i = i + 1 end
    return base .. " " .. i
end

-- Invoke fn(overrideHolder) for every raid auto-layout entry that carries an
-- `overrides` table (instanced/openWorld arrays + the single mythic profile).
local function ForEachRaidLayoutOverride(profile, fn)
    local rap = profile.raidAutoProfiles
    if type(rap) ~= "table" then return end
    for _, ctKey in ipairs({ "instanced", "openWorld", "mythic" }) do
        local ct = rap[ctKey]
        if type(ct) == "table" then
            if type(ct.profiles) == "table" then
                for _, layout in pairs(ct.profiles) do
                    if type(layout) == "table" and type(layout.overrides) == "table" then
                        fn(layout)
                    end
                end
            end
            if type(ct.profile) == "table" and type(ct.profile.overrides) == "table" then
                fn(ct.profile)
            end
        end
    end
end

local function MigrateDesigner(profile, libKey, refKey, inlineKey, factory)
    profile[libKey] = profile[libKey] or {}
    local lib = profile[libKey]
    if not lib[DF.DEFAULT_PRESET] then
        lib[DF.DEFAULT_PRESET] = factory()
    end

    -- Real party / raid → "Party" / "Raid" presets (always materialised so the
    -- two modes stay independent even when a mode had no inline config, e.g.
    -- lazily-initialised Text Designer).
    for _, mode in ipairs({ "party", "raid" }) do
        local modeDb = profile[mode]
        if modeDb then
            local presetName = DefaultPresetNameForMode(mode)
            if not lib[presetName] then
                if modeDb[inlineKey] then
                    lib[presetName] = modeDb[inlineKey]   -- move existing config in
                    modeDb[inlineKey] = nil
                else
                    lib[presetName] = factory()           -- materialise empty default
                end
            elseif modeDb[inlineKey] then
                modeDb[inlineKey] = nil                    -- preset exists; drop stray inline
            end
            if not modeDb[refKey] then
                modeDb[refKey] = presetName
            end
        end
    end

    -- Raid auto-layout whole-table overrides → uniquely-named presets, with the
    -- layout's override rewritten to the string key the overlay resolves by name.
    ForEachRaidLayoutOverride(profile, function(layout)
        local ovr = layout.overrides
        if ovr[inlineKey] then
            local name = UniquePresetName(lib, layout.name)
            lib[name] = ovr[inlineKey]
            ovr[inlineKey] = nil
            ovr[refKey] = name
        end
    end)
end

function DF:MigrateDesignerPresets()
    if not DandersFramesDB_v2 or not DandersFramesDB_v2.profiles then return end
    for _, profile in pairs(DandersFramesDB_v2.profiles) do
        if type(profile) == "table" then
            MigrateDesigner(profile, "auraDesignerPresets", "auraDesignerPreset",
                "auraDesigner", function() return DF:NewAuraDesignerConfig() end)
            MigrateDesigner(profile, "textDesignerPresets", "textDesignerPreset",
                "textDesigner", function() return DF:NewTextDesignerConfig() end)
        end
    end
end
