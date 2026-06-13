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

-- Deep value-equality for designer configs, IGNORING internal bookkeeping keys
-- (leading underscore, e.g. _specScopedV1/V2). Used to detect a per-layout
-- override that is just a stale full snapshot identical to the mode base — such
-- a redundant override should be dropped (the layout inherits the base) rather
-- than surfaced as a clutter preset.
local function DesignerConfigEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not (type(k) == "string" and k:sub(1, 1) == "_") then
            if not DesignerConfigEqual(v, b[k]) then return false end
        end
    end
    for k in pairs(b) do
        if not (type(k) == "string" and k:sub(1, 1) == "_") then
            if a[k] == nil then return false end
        end
    end
    return true
end

-- The preset a raid auto-layout would inherit if it had no override = whatever
-- the raid mode points at (default "Raid").
local function RaidBasePreset(profile, libKey, refKey)
    local lib = profile[libKey]
    if not lib then return nil end
    local raid = profile.raid
    local name = (raid and raid[refKey]) or "Raid"
    return lib[name]
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

    -- Raid auto-layout whole-table overrides → presets. A layout override that
    -- merely duplicates the mode base (a stale full snapshot from the old
    -- whole-table-override system) is dropped so the layout inherits the base,
    -- avoiding a clutter preset. Genuinely-different overrides become a
    -- uniquely-named preset the overlay resolves by name.
    local base = RaidBasePreset(profile, libKey, refKey)
    ForEachRaidLayoutOverride(profile, function(layout)
        local ovr = layout.overrides
        if ovr[inlineKey] then
            if base and DesignerConfigEqual(ovr[inlineKey], base) then
                ovr[inlineKey] = nil          -- redundant; inherit the base
            else
                local name = UniquePresetName(lib, layout.name)
                lib[name] = ovr[inlineKey]
                ovr[inlineKey] = nil
                ovr[refKey] = name
            end
        end
    end)
end

-- Is preset `name` still referenced by any consumer in this profile (party/raid
-- mode or a raid auto-layout override)? Used before pruning a redundant preset.
local function PresetReferenced(profile, refKey, name)
    if profile.party and profile.party[refKey] == name then return true end
    if profile.raid and profile.raid[refKey] == name then return true end
    local found = false
    ForEachRaidLayoutOverride(profile, function(layout)
        if layout.overrides[refKey] == name then found = true end
    end)
    return found
end

-- One-time cleanup for profiles migrated BEFORE the redundancy check existed:
-- a layout pointing at a layout-derived preset that deep-equals the mode base is
-- a stale snapshot — clear the override (inherit the base) and prune the preset
-- if nothing else references it. Genuinely-different layout presets are kept.
local function CleanupRedundantLayoutPresets(profile, libKey, refKey)
    local lib = profile[libKey]
    local base = RaidBasePreset(profile, libKey, refKey)
    if not lib or not base then return end
    local cleared = {}
    ForEachRaidLayoutOverride(profile, function(layout)
        local ovr = layout.overrides
        local name = ovr[refKey]
        if name and name ~= DF.DEFAULT_PRESET and name ~= "Party" and name ~= "Raid"
            and lib[name] and DesignerConfigEqual(lib[name], base) then
            ovr[refKey] = nil          -- inherit the mode base
            cleared[name] = true
        end
    end)
    for name in pairs(cleared) do
        if not PresetReferenced(profile, refKey, name) then
            lib[name] = nil            -- prune the now-orphaned redundant preset
        end
    end
end

function DF:MigrateDesignerPresets()
    if not DandersFramesDB_v2 or not DandersFramesDB_v2.profiles then return end
    for _, profile in pairs(DandersFramesDB_v2.profiles) do
        if type(profile) == "table" then
            MigrateDesigner(profile, "auraDesignerPresets", "auraDesignerPreset",
                "auraDesigner", function() return DF:NewAuraDesignerConfig() end)
            MigrateDesigner(profile, "textDesignerPresets", "textDesignerPreset",
                "textDesigner", function() return DF:NewTextDesignerConfig() end)
            -- Run the redundant-layout-preset cleanup ONCE per profile (so it
            -- tidies migration artifacts without later fighting a user who
            -- deliberately makes a layout preset identical to the base).
            if not profile._designerLayoutCleanupV1 then
                CleanupRedundantLayoutPresets(profile, "auraDesignerPresets", "auraDesignerPreset")
                CleanupRedundantLayoutPresets(profile, "textDesignerPresets", "textDesignerPreset")
                profile._designerLayoutCleanupV1 = true
            end
        end
    end
end

-- ============================================================
-- PRESET MANAGEMENT API (editor preset bar — Phase 2)
-- Library is per-profile (DF.db.<lib>); references are per-mode strings the
-- editor / consumers resolve by name. Operations update the current profile's
-- references only (party / raid / raid auto-layout overrides — pinned sets join
-- later). "Default" is non-deletable and non-renamable.
-- ============================================================

local DESIGNER_KINDS = {
    aura = { lib = "auraDesignerPresets", ref = "auraDesignerPreset" },
    text = { lib = "textDesignerPresets", ref = "textDesignerPreset" },
}

local function GetKindLib(kind)
    if kind == "aura" then return DF:GetAuraDesignerPresets() end
    return DF:GetTextDesignerPresets()
end

local function NewKindConfig(kind)
    if kind == "aura" then return DF:NewAuraDesignerConfig() end
    return DF:NewTextDesignerConfig()
end

-- Invoke fn(tbl) for every table in the CURRENT profile that holds a designer
-- preset reference under refKey: party, raid (real), and each raid auto-layout
-- override. (Pinned-set references will be added with the pinned integration.)
local function ForEachDesignerRef(fn)
    local prof = DF._realProfile or DF.db
    if not prof then return end
    if prof.party then fn(prof.party) end
    local raid = DF._realRaidDB or prof.raid
    if raid then fn(raid) end
    ForEachRaidLayoutOverride(prof, function(layout) fn(layout.overrides) end)
end

-- Sorted preset-name list for a dropdown ("Default" pinned first).
function DF:ListDesignerPresets(kind)
    local names = {}
    local lib = GetKindLib(kind)
    if lib then
        for name in pairs(lib) do
            if name ~= DF.DEFAULT_PRESET then names[#names + 1] = name end
        end
        table.sort(names)
        table.insert(names, 1, DF.DEFAULT_PRESET)
    end
    return names
end

-- Create a fresh (default) preset under a library-unique name. Returns the name.
function DF:CreateDesignerPreset(kind, name)
    local lib = GetKindLib(kind)
    if not lib then return nil end
    name = UniquePresetName(lib, name or "Preset")
    lib[name] = NewKindConfig(kind)
    return name
end

-- Deep-copy an existing preset under a new unique name. Returns the new name.
function DF:DuplicateDesignerPreset(kind, srcName, newName)
    local lib = GetKindLib(kind)
    if not lib or not lib[srcName] then return nil end
    newName = UniquePresetName(lib, newName or (srcName .. " copy"))
    lib[newName] = DF:DeepCopy(lib[srcName])
    return newName
end

-- Rename a preset and re-point every reference to it. Returns the final name,
-- or false if the rename can't proceed (Default / missing). The name is
-- uniquified, so the result may differ from newName.
function DF:RenameDesignerPreset(kind, oldName, newName)
    if oldName == DF.DEFAULT_PRESET then return false end
    local lib = GetKindLib(kind)
    if not lib or not lib[oldName] then return false end
    -- Uniquify against the library WITHOUT counting the entry being renamed.
    local saved = lib[oldName]
    lib[oldName] = nil
    newName = UniquePresetName(lib, newName or oldName)
    lib[newName] = saved
    if newName ~= oldName then
        local refKey = DESIGNER_KINDS[kind].ref
        ForEachDesignerRef(function(t)
            if t[refKey] == oldName then t[refKey] = newName end
        end)
    end
    return newName
end

-- Delete a preset; reassign every reference to it back to "Default". Returns
-- true on success (false for Default / missing).
function DF:DeleteDesignerPreset(kind, name)
    if name == DF.DEFAULT_PRESET then return false end
    local lib = GetKindLib(kind)
    if not lib or not lib[name] then return false end
    lib[name] = nil
    local refKey = DESIGNER_KINDS[kind].ref
    ForEachDesignerRef(function(t)
        if t[refKey] == name then t[refKey] = DF.DEFAULT_PRESET end
    end)
    return true
end

-- The preset NAME a mode currently resolves to (read through DF:GetDB so a raid
-- auto-layout's override of the name is reflected). Used by the editor bar.
function DF:GetModeDesignerPresetName(kind, mode)
    local refKey = DESIGNER_KINDS[kind] and DESIGNER_KINDS[kind].ref
    if not refKey then return DF.DEFAULT_PRESET end
    local modeDB = DF:GetDB(mode)
    return (modeDB and modeDB[refKey]) or DefaultPresetNameForMode(mode)
end

-- Point a mode at a preset by name. Raid writes go to the real raid table so
-- that, while a raid auto-layout is being edited, the AutoProfiles save-diff
-- captures it as a per-layout override of the preset NAME.
function DF:SetModeDesignerPreset(kind, mode, name)
    local refKey = DESIGNER_KINDS[kind].ref
    if mode == "raid" then
        local raid = DF._realRaidDB or (DF.db and DF.db.raid)
        if raid then raid[refKey] = name end
        -- While editing a raid auto-layout, also record an explicit override so
        -- the dropdown reflects the chosen preset (not "Inherit") even when its
        -- name happens to equal the global preset's. Inherit detection is based
        -- on this override's presence, not on name equality.
        local apu = DF.AutoProfilesUI
        if apu and apu.IsEditing and apu:IsEditing() and apu.editingProfile then
            apu.editingProfile.overrides = apu.editingProfile.overrides or {}
            apu.editingProfile.overrides[refKey] = name
        end
    else
        local prof = DF._realProfile or DF.db
        if prof and prof[mode] then prof[mode][refKey] = name end
    end
end

-- The reference key for a designer kind ("auraDesignerPreset" / "textDesignerPreset").
function DF:GetDesignerRefKey(kind)
    return DESIGNER_KINDS[kind] and DESIGNER_KINDS[kind].ref
end

-- While editing a raid auto-layout: is the layout currently INHERITING the
-- global designer preset? True when the layout has NO stored preset override —
-- based on override presence, NOT name equality, so explicitly picking a preset
-- whose name equals the global still reads as an override (shows its name).
function DF:IsLayoutDesignerInheriting(kind)
    local apu = DF.AutoProfilesUI
    if not (apu and apu.IsEditing and apu:IsEditing()) then return false end
    local refKey = DESIGNER_KINDS[kind] and DESIGNER_KINDS[kind].ref
    if not refKey then return false end
    local ovr = apu.editingProfile and apu.editingProfile.overrides
    return not (ovr and ovr[refKey] ~= nil)
end

-- While editing a raid auto-layout: clear the layout's designer-preset override
-- so the layout follows the global preset (the "Inherit (Global)" action; mirrors
-- the old Reset-to-Global). Drops any stored override and sets the live raid
-- value back to the snapshot global, so the save-diff records no override.
function DF:InheritLayoutDesignerPreset(kind)
    local apu = DF.AutoProfilesUI
    if not (apu and apu.IsEditing and apu:IsEditing()) then return end
    local refKey = DESIGNER_KINDS[kind] and DESIGNER_KINDS[kind].ref
    if not refKey then return end
    if apu.editingProfile and apu.editingProfile.overrides then
        apu.editingProfile.overrides[refKey] = nil
    end
    local glob = apu.globalSnapshot and apu.globalSnapshot[refKey]
    if DF._realRaidDB then DF._realRaidDB[refKey] = glob end
end
