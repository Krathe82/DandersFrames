local addonName, DF = ...

-- ============================================================
-- NICKNAMES
-- Replaces the displayed name on party/raid frames based on a
-- prioritised list of rules. The on-screen name flows through the
-- single DF:GetUnitName hook (see Frames/Core.lua + Frames/Bars.lua),
-- so teaching that one function to return a nickname is all it takes
-- to make nicknames appear everywhere the addon draws a name.
--
-- Features: account-wide storage; matching (exact + wildcard +
-- diacritic-normalised); the display hook; conflict/overlap analysis;
-- source pickers (group/guild/friends/B.net); an optional nickname marker;
-- and sharing (broadcast/accept, in Features/NicknamesComm.lua).
-- NOTE: the /dfnick slash command is dev-only scaffolding to retire before release.
-- ============================================================

local pairs, ipairs, type = pairs, ipairs, type
local tinsert, tremove = table.insert, table.remove
local strfind, strsub, strlower, gsub = string.find, string.sub, string.lower, string.gsub
local strmatch = string.match
local wipe = wipe
local UnitName = UnitName

DF.Nicknames = DF.Nicknames or {}
local NK = DF.Nicknames

NK.initialized = false

-- ============================================================
-- DIACRITIC NORMALISATION
-- WoW already enforces title-case for names, so case isn't the
-- concern — accents are. We strip diacritics so a plain-letter
-- pattern (mael*) matches both "Maelareth" and "Maëlareth".
-- Keys are the UTF-8 byte sequences of the accented characters.
-- A user who wants strict accent matching just types the accent
-- into their pattern (it normalises to itself only if absent here,
-- but since we strip on BOTH sides, "maël" still works for them).
-- ============================================================

local DIACRITICS = {
    ["à"]="a",["á"]="a",["â"]="a",["ã"]="a",["ä"]="a",["å"]="a",["æ"]="ae",
    ["ç"]="c",
    ["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",
    ["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",
    ["ñ"]="n",
    ["ò"]="o",["ó"]="o",["ô"]="o",["õ"]="o",["ö"]="o",["ø"]="o",["œ"]="oe",
    ["ù"]="u",["ú"]="u",["û"]="u",["ü"]="u",
    ["ý"]="y",["ÿ"]="y",
    ["ß"]="ss",
    -- Uppercase forms (covered after we lowercase, but kept for safety
    -- if normalisation order ever changes):
    ["À"]="a",["Á"]="a",["Â"]="a",["Ã"]="a",["Ä"]="a",["Å"]="a",["Æ"]="ae",
    ["Ç"]="c",
    ["È"]="e",["É"]="e",["Ê"]="e",["Ë"]="e",
    ["Ì"]="i",["Í"]="i",["Î"]="i",["Ï"]="i",
    ["Ñ"]="n",
    ["Ò"]="o",["Ó"]="o",["Ô"]="o",["Õ"]="o",["Ö"]="o",["Ø"]="o",["Œ"]="oe",
    ["Ù"]="u",["Ú"]="u",["Û"]="u",["Ü"]="u",
    ["Ý"]="y",
}

-- Lowercase + strip accents. Returns "" for nil/empty input.
function NK:Normalize(str)
    if not str or str == "" then return "" end
    str = strlower(str)
    -- Replace each known accented UTF-8 sequence with its base letter.
    for accented, base in pairs(DIACRITICS) do
        str = gsub(str, accented, base)
    end
    return str
end

-- ============================================================
-- STORAGE
-- Account-wide so a nickname follows you across every character
-- and every DandersFrames profile. Lives in the global bucket
-- (DandersFramesDB_v2.global) which is seeded in Core.lua and
-- persists through profile switches.
-- ============================================================

-- Returns the nicknames table { enabled = bool, entries = {...} },
-- creating it on first access. Returns nil only if saved vars aren't
-- loaded yet (shouldn't happen after ADDON_LOADED).
function NK:GetDB()
    if not DandersFramesDB_v2 then return nil end
    DandersFramesDB_v2.global = DandersFramesDB_v2.global or {}
    local g = DandersFramesDB_v2.global
    if not g.nicknames then
        g.nicknames = { enabled = true, entries = {} }
    end
    -- Phase 4 sharing/sync settings (backfilled so older saved-vars upgrade).
    local nk = g.nicknames
    if nk.selfNick   == nil then nk.selfNick   = "" end      -- your broadcast nickname
    if nk.shareVia   == nil then nk.shareVia   = "off" end   -- off | raid | guild | both
    if nk.acceptFrom == nil then nk.acceptFrom = "off" end   -- off | raid | guild | both
    if nk.autoSync   == nil then nk.autoSync   = true end     -- auto-broadcast on group join
    if nk.bracket    == nil then nk.bracket    = "off" end    -- legacy mark-scope (migrated below)
    if nk.markStyle  == nil then nk.markStyle  = "brackets" end -- decoration style
    if nk.markEnabled == nil then nk.markEnabled = (nk.bracket ~= "off") end  -- marker on/off toggle
    if nk.markScope  == nil then nk.markScope = (nk.bracket == "received") and "received" or "all" end  -- all | mine | received
    if nk.rejected   == nil then nk.rejected   = {} end       -- [normName] = true (blocked senders)
    return nk
end

-- ============================================================
-- NICKNAME MARKER DECORATION
-- Wraps a displayed nickname per the chosen style so it's visibly a nickname.
-- ASCII-only (the addon font lacks many fancy glyphs). "||" renders as a
-- single literal "|" in WoW FontStrings.
-- ============================================================
local NK_MARK_STYLES = {
    brackets = { "[", "]" },
    parens   = { "(", ")" },
    angle    = { "<", ">" },
    asterisk = { "",  "*" },
    pipe     = { "",  "||" },
}
local function decorateNick(nick, style)
    local s = NK_MARK_STYLES[style] or NK_MARK_STYLES.brackets
    return s[1] .. nick .. s[2]
end

-- ============================================================
-- MATCHING ENGINE
-- Each entry is one rule. The entries array IS the priority order:
-- index 1 is highest priority, and the first matching rule wins.
-- ============================================================

-- True if `hay` starts with `needle`.
local function startsWith(hay, needle)
    return strsub(hay, 1, #needle) == needle
end

-- True if `hay` ends with `needle`.
local function endsWith(hay, needle)
    return needle == "" or strsub(hay, -#needle) == needle
end

-- Does a single entry match the given (already-normalised) name/realm?
function NK:EntryMatches(entry, normName, normRealm, normFull)
    -- B.net rule: the unit matches if its current character is mapped to this
    -- rule's account in the live map (rebuilt from B.net friend info).
    if entry.kind == "bnet" then
        local map = NK.bnetNameMap
        if not map then return false end
        local id = (normFull and map[normFull]) or map[normName]
        return id ~= nil and id == entry.bnetID
    end

    -- Optional realm gate: if the rule names a realm, it must match.
    if entry.matchRealm and entry.matchRealm ~= "" then
        if normRealm ~= entry.matchRealm then return false end
    end

    local core = entry.matchName or ""
    if entry.kind == "wildcard" then
        if entry.wild == "prefix" then
            return startsWith(normName, core)
        elseif entry.wild == "suffix" then
            return endsWith(normName, core)
        else -- "contains"
            return strfind(normName, core, 1, true) ~= nil
        end
    else -- "exact"
        return normName == core
    end
end

-- Resolve a unit to a nickname string, or nil if no rule matches.
-- This is what the display hook calls.
function NK:Resolve(unit)
    local data = NK:GetDB()
    if not data or not data.enabled then return nil end

    local hasCurated = data.entries and #data.entries > 0
    local hasReceived = NK.received and next(NK.received) ~= nil
    if not hasCurated and not hasReceived then return nil end

    local name, realm = UnitName(unit)
    if not name or name == "" then return nil end
    -- UnitName returns "" / nil realm for same-realm units; fill in the
    -- player's own realm so "Name-MyRealm" rules still match them.
    if not realm or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    end

    local normName = NK:Normalize(name)
    local normRealm = NK:Normalize(realm)
    local normFull = (realm ~= "") and NK:Normalize(name .. "-" .. realm) or normName

    local marking = data.markEnabled
    local scope = data.markScope or "all"

    -- Your curated rules win (priority order).
    if hasCurated then
        for _, entry in ipairs(data.entries) do
            if NK:EntryMatches(entry, normName, normRealm, normFull) then
                local nick = entry.nickname
                if marking and (scope == "all" or scope == "mine") then
                    return decorateNick(nick, data.markStyle)
                end
                return nick
            end
        end
    end
    -- Fallback: a nickname someone shared with us (lowest priority).
    if hasReceived then
        local rec = NK:GetReceived(normFull, normName)
        if rec then
            if marking and (scope == "all" or scope == "received") then
                return decorateNick(rec, data.markStyle)
            end
            return rec
        end
    end
    return nil
end

-- ============================================================
-- CONFLICT / OVERLAP ANALYSIS
-- "covers": rule B matches every name rule A matches (B's set superset
--   of A's). If B is higher priority, A can never win -> A is shadowed.
-- "intersects": the two rules can both match at least one common name.
-- Used by the GUI to flag priority conflicts and overlaps.
-- ============================================================

-- Effective kind string for comparisons: "exact" / "prefix" / "suffix" / "contains".
local function effKind(e)
    if e.kind == "wildcard" then return e.wild end
    return "exact"
end

-- Could these two rules ever apply to the same realm?
local function realmCompatible(a, b)
    if a.matchRealm and a.matchRealm ~= "" and b.matchRealm and b.matchRealm ~= "" then
        return a.matchRealm == b.matchRealm
    end
    return true
end

-- Does B's match-set contain A's match-set?  (B superset of A)
local function covers(b, a)
    -- B.net rules match by account, not name — exclude from name-based analysis.
    if a.kind == "bnet" or b.kind == "bnet" then return false end
    -- A realm-restricted B can only cover A if A is restricted to the same
    -- realm (else A also matches other realms that B never will).
    if b.matchRealm and b.matchRealm ~= "" then
        if a.matchRealm ~= b.matchRealm then return false end
    end
    local bk, bc = effKind(b), b.matchName or ""
    local ak, ac = effKind(a), a.matchName or ""

    if bk == "exact" then
        return ak == "exact" and ac == bc
    elseif bk == "prefix" then
        if ak == "exact" or ak == "prefix" then return startsWith(ac, bc) end
        return false
    elseif bk == "suffix" then
        if ak == "exact" or ak == "suffix" then return endsWith(ac, bc) end
        return false
    else -- bk == "contains": every A-match contains bc iff A's core contains bc
        return strfind(ac, bc, 1, true) ~= nil
    end
end

-- Can A and B both match at least one common name?
local function intersects(a, b)
    if a.kind == "bnet" or b.kind == "bnet" then return false end
    if not realmCompatible(a, b) then return false end
    local ak, ac = effKind(a), a.matchName or ""
    local bk, bc = effKind(b), b.matchName or ""

    local function matchOne(kind, core, s)
        if kind == "exact" then return s == core
        elseif kind == "prefix" then return startsWith(s, core)
        elseif kind == "suffix" then return endsWith(s, core)
        else return strfind(s, core, 1, true) ~= nil end
    end

    -- If either is exact, just test that literal against the other rule.
    if ak == "exact" then return matchOne(bk, bc, ac) end
    if bk == "exact" then return matchOne(ak, ac, bc) end

    if ak == "prefix" and bk == "prefix" then
        return startsWith(ac, bc) or startsWith(bc, ac)
    elseif ak == "suffix" and bk == "suffix" then
        return endsWith(ac, bc) or endsWith(bc, ac)
    end
    -- Mixed wildcard types (contains-with-anything, or prefix+suffix): only
    -- flag when one core is contained in the other. A purely "constructible"
    -- overlap -- e.g. mael* and *mer* share only contrived names like
    -- "Maelmer" -- is too noisy to be worth flagging.
    return strfind(ac, bc, 1, true) ~= nil or strfind(bc, ac, 1, true) ~= nil
end

-- Returns an array parallel to entries:
--   out[i] = { shadowedBy = j|nil, overlaps = { idx, ... } }
-- shadowedBy: the first HIGHER-priority rule (j < i) that fully covers i,
--   meaning rule i can never win. overlaps: other rules that intersect i
--   but give a DIFFERENT nickname (same-nickname overlaps are harmless).
function NK:AnalyzeConflicts()
    local data = NK:GetDB()
    local entries = (data and data.entries) or {}
    local n = #entries
    local out = {}
    for i = 1, n do out[i] = { overlaps = {} } end

    for i = 1, n do
        local a = entries[i]
        for j = 1, i - 1 do
            if covers(entries[j], a) then
                out[i].shadowedBy = j
                break
            end
        end
    end

    for i = 1, n do
        for j = i + 1, n do
            local a, b = entries[i], entries[j]
            if a.nickname ~= b.nickname and intersects(a, b) then
                tinsert(out[i].overlaps, j)
                tinsert(out[j].overlaps, i)
            end
        end
    end
    return out
end

-- ============================================================
-- DISPLAY HOOK
-- Wrap DF:GetUnitName so it returns the nickname when a rule
-- matches, falling back to whatever was there before (the default
-- implementation, or an external addon's override). Chaining like
-- this keeps us a good citizen in the addon ecosystem.
-- ============================================================

function NK:InstallHook()
    if NK._hookInstalled then return end
    NK._hookInstalled = true

    local previous = DF.GetUnitName  -- default impl from Frames/Core.lua
    DF.GetUnitName = function(selfDF, unit)
        local nick = NK:Resolve(unit)
        if nick then return nick end
        if previous then return previous(selfDF, unit) end
        return UnitName(unit) or unit
    end
end

-- Force every visible frame to re-read its name. Call after any edit.
-- Names can be drawn by two systems, so we nudge both:
--   * legacy nameText  -> DF:UpdateName
--   * Text Designer    -> DF:UpdateTextDesigner (re-renders via the Live
--     data source, whose GetName() calls our hooked DF:GetUnitName)
-- Whichever one is active on the user's build, the nickname shows.
function NK:RefreshAllFrames()
    if DF.IterateCompactFrames then
        DF:IterateCompactFrames(function(frame)
            if DF.UpdateName then DF:UpdateName(frame) end
            if DF.UpdateTextDesigner then DF:UpdateTextDesigner(frame) end
        end)
    end
    -- Notify any UI listener (e.g. the options panel) so it stays in sync no
    -- matter where the change came from (GUI, /dfnick, future sharing, ...).
    if NK.onChange then NK.onChange() end
end

-- ============================================================
-- ENTRY HELPERS (used by the GUI add/edit flow)
-- ============================================================

-- Build an exact-name entry table (no insert). `nameInput` may include
-- a realm as "Name-Realm".
local function buildExact(nameInput, nickname, source)
    local namePart, realmPart = strmatch(nameInput, "^([^%-]+)%-(.+)$")
    namePart = namePart or nameInput
    return {
        kind = "exact",
        pattern = nameInput,
        matchName = NK:Normalize(namePart),
        realm = realmPart,
        matchRealm = realmPart and NK:Normalize(realmPart) or nil,
        nickname = nickname,
        source = source or "Manual",
    }
end

-- Build an entry with an EXPLICIT match type (no '*' parsing). Used by the
-- GUI match-type dropdown so intent is unambiguous.
-- matchType: "exact" | "prefix" | "suffix" | "contains".
function NK:BuildTyped(matchType, text, nickname, source)
    if not text or text == "" or not nickname or nickname == "" then return nil end
    if matchType == "exact" or not matchType then
        return buildExact(text, nickname, source)
    end
    local core = gsub(text, "%*", "")  -- ignore any stray asterisks
    if core == "" then return nil end
    return {
        kind = "wildcard",
        wild = matchType,
        pattern = core,
        matchName = NK:Normalize(core),
        nickname = nickname,
        source = source or "Wildcard",
    }
end

function NK:AddTyped(matchType, text, nickname, source)
    local data = NK:GetDB()
    if not data then return nil end
    local entry = NK:BuildTyped(matchType, text, nickname, source)
    if not entry then return nil end
    tinsert(data.entries, entry)
    NK:RefreshAllFrames()
    return entry
end

function NK:SetEntryTyped(index, matchType, text, nickname, source)
    local data = NK:GetDB()
    if not data or not data.entries[index] then return false end
    local entry = NK:BuildTyped(matchType, text, nickname, source or data.entries[index].source)
    if not entry then return false end
    data.entries[index] = entry
    NK:RefreshAllFrames()
    return true
end

function NK:RemoveAt(index)
    local data = NK:GetDB()
    if not data or not data.entries[index] then return false end
    tremove(data.entries, index)
    NK:RefreshAllFrames()
    return true
end

-- Move the rule at `from` to position `to` (reordering = changing priority,
-- since the list IS the priority order). Used by drag-to-reorder.
function NK:MoveEntry(from, to)
    local data = NK:GetDB()
    if not data then return false end
    local n = #data.entries
    if not from or from < 1 or from > n then return false end
    to = math.max(1, math.min(to or n, n))
    if to == from then return false end
    local e = tremove(data.entries, from)
    tinsert(data.entries, to, e)
    NK:RefreshAllFrames()
    return true
end

function NK:Clear()
    local data = NK:GetDB()
    if not data then return end
    wipe(data.entries)
    NK:RefreshAllFrames()
end

-- ============================================================
-- SOURCE ENUMERATORS  (Phase 2 — feed the "Add from..." pickers)
-- Each returns an array of candidates:
--   { name=, realm=, fullName="Name-Realm", class=<token|nil>, online=bool }
-- Pure data; the picker UI lives in Options/NicknamesPicker.lua.
-- These social rosters are out-of-combat APIs, unaffected by Midnight's
-- Secret Values restrictions.
-- ============================================================

local function pushCandidate(out, name, realm, class, online)
    if not name or name == "" then return end
    if not realm or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    end
    local full = (realm ~= "") and (name .. "-" .. realm) or name
    tinsert(out, { name = name, realm = realm, fullName = full, class = class, online = online })
end

-- Current party/raid (includes the player). Solo returns just the player.
function NK:GetGroupCandidates()
    local out = {}
    local n = GetNumGroupMembers() or 0
    if n == 0 then
        local name, realm = UnitName("player")
        local _, class = UnitClass("player")
        pushCandidate(out, name, realm, class, true)
        return out
    end
    local isRaid = IsInRaid()
    for i = 1, n do
        local unit = isRaid and ("raid" .. i) or (i == 1 and "player" or "party" .. (i - 1))
        local name, realm = UnitName(unit)
        local _, class = UnitClass(unit)
        pushCandidate(out, name, realm, class, UnitIsConnected(unit))
    end
    return out
end

-- Guild roster.
function NK:GetGuildCandidates()
    local out = {}
    if not IsInGuild() then return out end
    -- Ask the server to refresh (async); cached data is usually ready on reopen.
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local fullName, _, _, _, _, _, _, _, online, _, classToken = GetGuildRosterInfo(i)
        if fullName then
            local name, realm = strsplit("-", fullName)
            pushCandidate(out, name, realm, classToken, online)
        end
    end
    return out
end

-- In-game friends.
function NK:GetFriendCandidates()
    local out = {}
    if not (C_FriendList and C_FriendList.GetNumFriends) then return out end
    if C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
    local n = C_FriendList.GetNumFriends() or 0
    for i = 1, n do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name then
            local name, realm = strsplit("-", info.name)
            -- FriendInfo gives a localised class name, not a token, so class
            -- stays nil (neutral colour) for now.
            pushCandidate(out, name, realm, nil, info.connected)
        end
    end
    return out
end

-- True if an EXACT rule already covers this character (marks a picker
-- candidate as "already added").
function NK:HasRuleFor(name, realm)
    local data = NK:GetDB()
    if not data then return false end
    local nN = NK:Normalize(name)
    local nR = realm and NK:Normalize(realm) or nil
    for _, e in ipairs(data.entries) do
        if e.kind == "exact" and e.matchName == nN then
            if not e.matchRealm or not nR or e.matchRealm == nR then
                return true
            end
        end
    end
    return false
end

-- B.net friends (account-based). Returns:
--   { bnetID=, label=, battleTag=, currentChar="Name-Realm"|nil, online=bool }
-- currentChar is the friend's active WoW character if the API reports it.
function NK:GetBnetCandidates()
    local out = {}
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then
        return out
    end
    local total = BNGetNumFriends() or 0
    for i = 1, total do
        local acc = C_BattleNet.GetFriendAccountInfo(i)
        if acc and acc.bnetAccountID then
            local label = (acc.accountName and acc.accountName ~= "" and acc.accountName)
                or acc.battleTag or ("BNet " .. i)
            local currentChar, online
            local ng = (C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendNumGameAccounts(i)) or 0
            for g = 1, ng do
                local ga = C_BattleNet.GetFriendGameAccountInfo(i, g)
                if ga and ga.clientProgram == "WoW" and ga.characterName then
                    currentChar = ga.characterName .. (ga.realmName and ("-" .. ga.realmName) or "")
                    online = true
                    break
                end
            end
            tinsert(out, {
                bnetID = acc.bnetAccountID,
                label = label,
                battleTag = acc.battleTag,
                currentChar = currentChar,
                online = online,
            })
        end
    end
    return out
end

-- ============================================================
-- B.NET RULES (account-based; "follows the friend across characters")
-- A rule stores a stable bnetAccountID. We keep a live map of each
-- nicknamed friend's CURRENT WoW character name -> their account id,
-- rebuilt whenever B.net/roster info changes; EntryMatches consults it.
-- ============================================================

NK.bnetNameMap = NK.bnetNameMap or {}

function NK:HasBnetRule(bnetID)
    local data = NK:GetDB()
    if not data or not bnetID then return false end
    for _, e in ipairs(data.entries) do
        if e.kind == "bnet" and e.bnetID == bnetID then return true end
    end
    return false
end

-- Add a B.net rule. `label` is a display string (battleTag / account name).
function NK:AddBnet(bnetID, label, nickname)
    local data = NK:GetDB()
    if not data or not bnetID or not nickname or nickname == "" then return nil end
    local entry = {
        kind = "bnet",
        bnetID = bnetID,
        pattern = label or tostring(bnetID),
        nickname = nickname,
        source = "B.net",
    }
    tinsert(data.entries, entry)
    NK:RebuildBnetMap()
    NK:RefreshAllFrames()
    return entry
end

-- Update only the nickname of the rule at `index` (used when editing a B.net
-- rule, whose "character" isn't an editable field).
function NK:SetNickname(index, nickname)
    local data = NK:GetDB()
    local e = data and data.entries[index]
    if not e or not nickname or nickname == "" then return false end
    e.nickname = nickname
    NK:RebuildBnetMap()
    NK:RefreshAllFrames()
    return true
end

-- Rebuild the live "current character -> account id" map from B.net friends
-- who have a rule. Cheap no-op when there are no B.net rules.
function NK:RebuildBnetMap()
    NK.bnetNameMap = NK.bnetNameMap or {}
    wipe(NK.bnetNameMap)
    local data = NK:GetDB()
    if not data then return end

    local wanted, any = {}, false
    for _, e in ipairs(data.entries) do
        if e.kind == "bnet" and e.bnetID then wanted[e.bnetID] = true; any = true end
    end
    if not any then return end
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end

    local total = BNGetNumFriends() or 0
    for i = 1, total do
        local acc = C_BattleNet.GetFriendAccountInfo(i)
        if acc and acc.bnetAccountID and wanted[acc.bnetAccountID] then
            local ng = (C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendNumGameAccounts(i)) or 0
            for g = 1, ng do
                local ga = C_BattleNet.GetFriendGameAccountInfo(i, g)
                if ga and ga.clientProgram == "WoW" and ga.characterName then
                    if ga.realmName and ga.realmName ~= "" then
                        NK.bnetNameMap[NK:Normalize(ga.characterName .. "-" .. ga.realmName)] = acc.bnetAccountID
                    end
                    NK.bnetNameMap[NK:Normalize(ga.characterName)] = acc.bnetAccountID
                end
            end
        end
    end
end

-- Debounced rebuild + frame refresh, fired by B.net / roster events.
function NK:ScheduleBnetRebuild()
    if NK._bnetRebuildPending then return end
    NK._bnetRebuildPending = true
    C_Timer.After(1, function()
        NK._bnetRebuildPending = false
        local data = NK:GetDB()
        local hasBnet = false
        if data then
            for _, e in ipairs(data.entries) do
                if e.kind == "bnet" then hasBnet = true break end
            end
        end
        if not hasBnet then return end
        NK:RebuildBnetMap()
        NK:RefreshAllFrames()
    end)
end

-- ============================================================
-- RECEIVED NICKNAMES (Phase 4 — shared to us by other users)
-- Kept SEPARATE from the curated list (NK.received, session-only) and used
-- only as a LOWEST-priority fallback in Resolve, so your own rules always
-- win. The comm layer (next slice) fills this from broadcasts; for now a
-- dev command (/dfnick recv) can simulate an incoming nickname.
-- ============================================================

NK.received = NK.received or {}  -- [normFull | normName] = { nick=, sender= }

-- Store a received nickname for a character. `fullName` is "Name-Realm" (the
-- sender reported by the addon message, or an explicit name when simulating).
-- Incoming-nickname sanitiser. Used for received broadcasts AND plain imports.
-- Returns a cleaned nickname, or nil to reject. Blizzard's name/profanity
-- filters are NOT exposed to addons, so we sanitise ourselves. The important
-- guard is stripping UI escape codes (anti-injection); the bad-word list is a
-- small politeness layer (expand over time).
local NK_MAX_NICK_LEN = 32
local NK_BADWORDS = {
    -- compact starter list (lowercase substrings); expand as needed.
    "fuck", "shit", "cunt", "bitch", "nigger", "faggot", "retard",
}
-- Returns (cleanNick) on success, or (nil, reason) on rejection.
-- reason: "empty" | "escape" | "toolong" | "profanity".
function NK:FilterIncoming(nick)
    if type(nick) ~= "string" then return nil, "empty" end
    nick = nick:gsub("^%s+", ""):gsub("%s+$", "")           -- trim
    if nick == "" then return nil, "empty" end
    if strfind(nick, "|", 1, true) then return nil, "escape" end   -- UI escape codes (|c |H |T |r ...)
    if strfind(nick, "[%z\1-\31]") then return nil, "escape" end    -- control bytes / newlines
    local len = (DF.UTF8Len and DF:UTF8Len(nick)) or #nick
    if len > NK_MAX_NICK_LEN then return nil, "toolong" end
    -- Whole-word match only (avoids the "Scunthorpe problem", where a clean
    -- word contains a banned substring). Fold accents via Normalize, then split
    -- on non-letters so "cunt", "you cunt", and "cunt123" are caught, but
    -- "Scunthorpe" / "class" / "Penistone" are not.
    local folded = NK:Normalize(nick)
    for token in folded:gmatch("%a+") do
        for _, w in ipairs(NK_BADWORDS) do
            if token == w then return nil, "profanity" end
        end
    end
    return nick
end

-- Sanitise a raw incoming nickname for SAFE DISPLAY (it may contain the very
-- escape codes we reject): escape pipes so they render literally, drop control
-- bytes, cap length.
local function displaySafe(s)
    s = (type(s) == "string" and s or "?"):gsub("|", "||"):gsub("[%z\1-\31]", "?")
    if #s > 40 then s = s:sub(1, 40) .. "..." end
    return s
end

-- Store a received nickname. Rather than silently dropping a rejected one, we
-- keep it in the Received list FLAGGED as blocked (with a reason) so the user
-- can see what came in and catch false positives. Blocked entries never
-- display on frames (GetReceived skips them).
function NK:AddReceived(fullName, nick, sender)
    if not fullName or fullName == "" then return end
    sender = sender or fullName

    local clean, reason = NK:FilterIncoming(nick)
    local entry
    if clean then
        local data = NK:GetDB()
        local userBlocked = data and data.rejected and data.rejected[NK:Normalize(sender)] or false
        entry = { nick = clean, sender = sender,
                  blocked = userBlocked and true or false,
                  reason = userBlocked and "user" or nil }
    else
        entry = { nick = displaySafe(nick), sender = sender, blocked = true, reason = reason }
    end

    NK.received = NK.received or {}
    local name = strsplit("-", fullName)
    NK.received[NK:Normalize(fullName)] = entry
    if name and name ~= "" then NK.received[NK:Normalize(name)] = entry end
    NK:RefreshAllFrames()
end

-- User block / unblock for a sender (persisted in `rejected`). Filter-blocked
-- entries stay blocked regardless; only user-blocks are reversible here.
function NK:BlockSender(sender)
    local data = NK:GetDB()
    if not data or not sender then return end
    data.rejected = data.rejected or {}
    local key = NK:Normalize(sender)
    data.rejected[key] = true
    for _, e in pairs(NK.received or {}) do
        if e.sender and NK:Normalize(e.sender) == key then
            e.blocked = true
            if not e.reason then e.reason = "user" end
        end
    end
    NK:RefreshAllFrames()
end

function NK:UnblockSender(sender)
    local data = NK:GetDB()
    if not data or not sender then return end
    local key = NK:Normalize(sender)
    if data.rejected then data.rejected[key] = nil end
    for _, e in pairs(NK.received or {}) do
        if e.sender and NK:Normalize(e.sender) == key and e.reason == "user" then
            e.blocked = false
            e.reason = nil
        end
    end
    NK:RefreshAllFrames()
end

function NK:ClearReceived()
    NK.received = {}
    NK:RefreshAllFrames()
end

-- Look up a received nickname by a unit's normalized full/short name.
function NK:GetReceived(normFull, normName)
    local r = NK.received
    if not r then return nil end
    local e = (normFull and r[normFull]) or r[normName]
    if e and not e.blocked then return e.nick end  -- blocked entries never display
    return nil
end

-- De-duplicated list of received entries for the UI: { {sender=, nick=}, ... }
-- (NK.received stores each entry under both full- and short-name keys, so we
-- dedupe by the shared entry table.)
function NK:GetReceivedList()
    local out, seen = {}, {}
    for _, e in pairs(NK.received or {}) do
        if e and not seen[e] then
            seen[e] = true
            tinsert(out, { sender = e.sender, nick = e.nick, blocked = e.blocked, reason = e.reason })
        end
    end
    return out
end

-- Drop all received entries from a given sender.
function NK:RemoveReceived(sender)
    if not NK.received or not sender then return end
    for k, e in pairs(NK.received) do
        if e.sender == sender then NK.received[k] = nil end
    end
    NK:RefreshAllFrames()
end

-- ============================================================
-- INIT  (called from Core.lua after PLAYER_LOGIN)
-- ============================================================

function NK:Init()
    if self.initialized then return end
    self.initialized = true

    NK:InstallHook()

    -- B.net "follow the account" map: build now and keep it fresh as friends
    -- log in/out or switch characters.
    NK:RebuildBnetMap()
    local bf = CreateFrame("Frame")
    bf:RegisterEvent("BN_FRIEND_INFO_CHANGED")
    bf:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
    bf:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
    bf:RegisterEvent("GROUP_ROSTER_UPDATE")
    bf:SetScript("OnEvent", function() NK:ScheduleBnetRebuild() end)
    NK._bnetEventFrame = bf

    -- Nickname sharing/comms layer (Phase 4).
    if DF.NicknamesComm then DF.NicknamesComm:Init() end

    -- Make sure any names already on screen pick up existing rules.
    NK:RefreshAllFrames()
end
