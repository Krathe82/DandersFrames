local addonName, DF = ...

-- ============================================================
-- ATTACHMENT SCAN (diagnostic)
-- Lists frames from OTHER addons that are anchored to, or parented
-- onto, DandersFrames unit frames. Helps users tell DF's own
-- features apart from castbars / cooldowns / auras that another
-- addon has attached to our frames.
--
-- Read-only and run on demand via `/df attached`. WoW has no
-- "frame -> owning addon" API, so addon attribution is a best-effort
-- name heuristic; unknown frames are reported with their type and
-- attach method so the user can investigate.
--
-- Reliable case: a frame anchored (SetPoint) to a DF frame whose own
-- parent chain is NOT inside DF -> definitely foreign.
-- Limitation: a foreign frame RE-PARENTED onto a DF frame is
-- indistinguishable from a DF-created child without ownership tagging,
-- so we only flag re-parented frames that carry a non-DF name.
-- ============================================================

local pairs, ipairs = pairs, ipairs
local format = string.format
local tinsert, tsort = table.insert, table.sort
local pcall = pcall
local EnumerateFrames = EnumerateFrames

-- Known addons keyed by a lowercase substring found in their frame names.
-- Best-effort only — extend as we see new culprits in bug reports.
local KNOWN_ADDONS = {
    { pat = "quartz",     name = "Quartz" },
    { pat = "weakauras",  name = "WeakAuras" },
    { pat = "plater",     name = "Plater" },
    { pat = "omnicc",     name = "OmniCC" },
    { pat = "minicc",     name = "MiniCC" },
    { pat = "details",    name = "Details!" },
    { pat = "bigwigs",    name = "BigWigs" },
    { pat = "littlewigs", name = "LittleWigs" },
    { pat = "cell",       name = "Cell" },
    { pat = "elvuf",      name = "ElvUI" },
    { pat = "elvui",      name = "ElvUI" },
    { pat = "grid2",      name = "Grid2" },
    { pat = "vuhdo",      name = "VuhDo" },
    { pat = "clique",     name = "Clique" },
    { pat = "gladius",    name = "Gladius" },
    { pat = "sarena",     name = "sArena" },
    { pat = "tellmewhen", name = "TellMeWhen" },
    { pat = "nugrunning", name = "NugRunning" },
    { pat = "hekili",     name = "Hekili" },
    { pat = "exrt",       name = "MethodRaidTools/exRT" },
    { pat = "w-method",   name = "MethodRaidTools" },
}

-- Derive a probable addon name from a frame name's leading token, e.g.
-- "MiniCC_Container_57" -> "MiniCC", "QuartzCastBarplayer" -> "Quartz".
-- Returns nil for names too short/generic to be meaningful.
local function DerivePrefix(name)
    -- Leading alphabetic run, stopping at first underscore or digit.
    local prefix = name:match("^(%a+)")
    if not prefix or #prefix < 3 then return nil end
    -- Generic container words aren't addon names on their own.
    local lower = prefix:lower()
    if lower == "frame" or lower == "button" or lower == "container"
       or lower == "ui" or lower == "status" then
        return nil
    end
    return prefix
end

-- Best-effort source addon for a frame.
-- Returns: displayName, confident. displayName is nil only when nothing resolved.
--
-- Primary method (no curated list needed): a globally-named frame's global was
-- written by its creating addon, which taints that variable. issecurevariable
-- reports the tainting addon's name — e.g. "Party1SpellBar" -> "BetterBlizzFrames".
local function GuessAddon(frame)
    local name = frame:GetName()

    -- 1. Taint ownership of the frame's global. Most reliable; real folder name.
    if name and name ~= "" and _G[name] == frame then
        local ok, isSecure, taintAddon = pcall(issecurevariable, name)
        if ok and not isSecure and taintAddon and taintAddon ~= "" then
            return taintAddon, true
        end
    end

    local names = {}
    if name and name ~= "" then names[#names + 1] = name end
    if frame.GetDebugName then
        local ok, dn = pcall(frame.GetDebugName, frame)
        if ok and dn and dn ~= "" then names[#names + 1] = dn end
    end
    -- 2. Curated list — canonicalises names that don't match the folder
    --    (e.g. ElvUF -> ElvUI) and covers frames with no global taint.
    for _, s in ipairs(names) do
        local low = s:lower()
        for _, entry in ipairs(KNOWN_ADDONS) do
            if low:find(entry.pat, 1, true) then
                return entry.name, true
            end
        end
    end
    -- 3. Last resort: leading token of the frame's own name.
    for _, s in ipairs(names) do
        local prefix = DerivePrefix(s)
        if prefix then return prefix, false end
    end
    return nil, false
end

-- True for a WoW widget (frame/region), false for plain Lua tables.
local function IsWidget(v)
    return type(v) == "table" and type(v.GetObjectType) == "function"
        and type(v.GetParent) == "function"
end

-- Build the set of DF frames: headers, unit buttons, the documented
-- sub-elements other addons commonly anchor to, AND every widget DF stores
-- as a field on a unit button. The last part matters because DF parents some
-- of its own overlays (highlight borders, Aura Designer borders) to UIParent
-- to avoid clipping — those aren't reachable by an ancestor walk, but they ARE
-- referenced from the button (frame.dfSelectionHighlight, frame.dfAD_border…).
-- Returns set = { [frame] = "label" }.
local function BuildDFFrameSet()
    local set = {}

    local SUBS = {
        healthBar = ".healthBar", powerBar = ".powerBar", castBar = ".castBar",
        contentOverlay = ".contentOverlay", border = ".border",
        background = ".background", nameText = ".nameText", healthText = ".healthText",
    }

    -- Collect widgets DF stashed on the button: direct fields (frame.dfFoo) and
    -- one level into table fields (frame.dfAD_customBorders = { ... }).
    local function collectOwned(frame, label)
        for k, v in pairs(frame) do
            if IsWidget(v) then
                if not set[v] then set[v] = label .. "#" .. tostring(k) end
            elseif type(v) == "table" then
                for _, vv in pairs(v) do
                    if IsWidget(vv) and not set[vv] then
                        set[vv] = label .. "#" .. tostring(k)
                    end
                end
            end
        end
    end

    local function addUnit(frame, label)
        if not frame then return end
        set[frame] = label
        for key, suffix in pairs(SUBS) do
            local sub = frame[key]
            if sub then set[sub] = label .. suffix end
        end
        collectOwned(frame, label)
    end

    if DF.IteratePartyFrames then
        DF:IteratePartyFrames(function(f, _, unit) addUnit(f, unit) end)
    end
    if DF.IterateRaidFrames then
        DF:IterateRaidFrames(function(f, _, unit) addUnit(f, unit) end)
    end
    if DF.IterateArenaFrames then
        DF:IterateArenaFrames(function(f, _, unit) addUnit(f, "arena:" .. unit) end)
    end

    -- Headers / containers so the ancestor walk still recognises DF
    -- descendants whose unit button wasn't iterated (e.g. hidden frames).
    local roots = { DF.partyHeader, DF.partyContainer, DF.arenaHeader }
    if DF.raidSeparatedHeaders then
        for _, h in pairs(DF.raidSeparatedHeaders) do roots[#roots + 1] = h end
    end
    if DF.FlatRaidFrames and DF.FlatRaidFrames.header then
        roots[#roots + 1] = DF.FlatRaidFrames.header
    end
    for _, h in ipairs(roots) do
        if h and not set[h] then set[h] = (h.GetName and h:GetName()) or "DFHeader" end
    end

    return set
end

-- Walk the parent chain; true if any ancestor (or the frame itself) is a DF frame.
local function IsInDFTree(frame, dfSet)
    local f, guard = frame, 0
    while f and guard < 80 do
        if dfSet[f] then return true end
        f = f:GetParent()
        guard = guard + 1
    end
    return false
end

function DF:ScanFrameAttachments()
    local dfSet = BuildDFFrameSet()

    local results = {}   -- [label] = { { otype, name, addon, kind }, ... }
    local total = 0

    local function record(label, foreign, kind)
        local addon, curated = GuessAddon(foreign)
        results[label] = results[label] or {}
        tinsert(results[label], {
            otype   = foreign:GetObjectType() or "?",
            name    = foreign:GetName(),
            addon   = addon,
            curated = curated,
            kind    = kind,
        })
        total = total + 1
    end

    local scanned = 0
    local f = EnumerateFrames()
    while f do
        scanned = scanned + 1
        if not f:IsForbidden() and not IsInDFTree(f, dfSet) then
            local parent = f:GetParent()
            if parent and dfSet[parent] then
                -- Re-parented onto a DF frame. Only report if it carries a
                -- non-DF name (anonymous re-parents can't be told apart from
                -- DF's own anonymous children, so we skip those).
                local nm = f:GetName()
                if nm and not nm:find("Danders", 1, true) then
                    record(dfSet[parent], f, "parented")
                end
            else
                -- Anchored (SetPoint) to a DF frame without re-parenting.
                local np = f:GetNumPoints() or 0
                for i = 1, np do
                    local ok, _, relTo = pcall(f.GetPoint, f, i)
                    if ok and relTo and dfSet[relTo] then
                        record(dfSet[relTo], f, "anchored")
                        break
                    end
                end
            end
        end
        f = EnumerateFrames(f)
    end

    print(format("|cff00ff00DandersFrames:|r foreign-attachment scan — %d frames scanned", scanned))
    if total == 0 then
        print("  No other addons appear to be attached to DandersFrames unit frames.")
        print("  (Note: a foreign frame re-parented onto ours with no name can't be detected.)")
        return
    end

    local labels = {}
    for label in pairs(results) do labels[#labels + 1] = label end
    tsort(labels)

    for _, label in ipairs(labels) do
        print("|cffffd100" .. label .. ":|r")
        for _, e in ipairs(results[label]) do
            local who
            if e.addon and e.curated then
                who = e.addon                       -- confident, from curated list
            elseif e.addon then
                who = e.addon .. "|cffaaaaaa?|r"     -- guessed from frame name
            else
                who = "|cffaaaaaaunknown addon|r"
            end
            local nm = e.name or "<anonymous>"
            print(format("    %s  —  %s [%s, %s]", who, nm, e.otype, e.kind))
        end
    end
    print(format("  %d attachment(s) found across %d frame(s).", total, #labels))
end
