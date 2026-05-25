local addonName, DF = ...

-- ============================================================
-- TEXT DESIGNER — RESOLVER
-- Maps (elem, source) -> display string.
-- One function per content type in CONTENT_TYPES.
-- All output is a string ready for FontString:SetText.
-- ============================================================

DF.TextDesigner = DF.TextDesigner or {}
local Resolver = {}
DF.TextDesigner.Resolver = Resolver

local MS  -- lazy resolve
local function getMS()
    if not MS then MS = DF.TextDesigner.MidnightSafe end
    return MS
end

-- ============================================================
-- HELPERS
-- ============================================================

-- Truncate / ellipsize a name string per the per-element name settings.
local function applyNameTrunc(name, elem)
    local maxLen = elem.nameLength or 30
    if #name <= maxLen then return name end
    local mode = elem.truncateMode or "ELLIPSIS"
    if mode == "ELLIPSIS" then
        return name:sub(1, maxLen - 1) .. "…"
    else
        return name:sub(1, maxLen)
    end
end

-- ============================================================
-- INDIVIDUAL RESOLVERS
-- ============================================================

local RESOLVERS = {}

-- ───── Identity ─────

RESOLVERS.name = function(elem, source)
    local n = source:GetName()
    if not n or n == "" then return "" end
    return applyNameTrunc(getMS().SafeText(n), elem)
end

RESOLVERS.class = function(elem, source)
    -- Display localized name by default
    return getMS().SafeText(source:GetClassLocalized())
end

RESOLVERS.group_number = function(elem, source)
    local n = source:GetGroupNumber()
    if not n then return "" end
    local fmt = elem.groupFormat or "STANDALONE"
    if fmt == "PREFIX" then return "G" .. tostring(n)
    elseif fmt == "SUFFIX" then return tostring(n)
    else return "G" .. tostring(n) end  -- STANDALONE default
end

RESOLVERS.race_level_faction = function(elem, source)
    local race = source:GetRace() or ""
    local lvl = source:GetLevel() or "??"
    local fac = source:GetFaction() or ""
    -- Format: "80 Draenei (Alliance)" — adjust per elem.format if needed
    local parts = {}
    if lvl and lvl ~= "" then parts[#parts+1] = tostring(lvl) end
    if race and race ~= "" then parts[#parts+1] = race end
    local s = table.concat(parts, " ")
    if fac and fac ~= "" then s = s .. " (" .. fac .. ")" end
    return s
end

RESOLVERS.custom_static = function(elem, source)
    return elem.staticText or ""
end

-- ───── Health ─────

RESOLVERS.hp_current = function(elem, source)
    return getMS().FormatNumber(source:GetHPCurrent(), elem.abbreviate)
end

RESOLVERS.hp_max = function(elem, source)
    return getMS().FormatNumber(source:GetHPMax(), elem.abbreviate)
end

RESOLVERS.hp_percent = function(elem, source)
    return getMS().PctText(source:GetHPPercent(), elem.decimals or 0)
end

RESOLVERS.hp_deficit = function(elem, source)
    local v = source:GetHPDeficit()
    if v == nil then return "" end
    local s = getMS().Truncate(v)
    if s == "" then return "" end
    if elem.abbreviate then s = getMS().Abbr(v) end
    return "-" .. s
end

RESOLVERS.hp_max_reduction = function(elem, source)
    local pct = source:GetHPMaxReductionPct() or 0
    if pct == 0 then return "" end
    -- API returns 0..1 in some patches and 0..100 in others.
    -- Defensive: if value is <= 1, multiply by 100 for display.
    local v = pct
    if pct <= 1 then v = pct * 100 end
    return string.format("-%.0f%%", v)
end

-- ───── Power ─────

RESOLVERS.power_current = function(elem, source)
    return getMS().FormatNumber(source:GetPowerCurrent(), elem.abbreviate)
end

RESOLVERS.power_percent = function(elem, source)
    return getMS().PctText(source:GetPowerPercent(), elem.decimals or 0)
end

RESOLVERS.power_deficit = function(elem, source)
    local v = source:GetPowerDeficit()
    if v == nil then return "" end
    local s = getMS().Truncate(v)
    if s == "" then return "" end
    if elem.abbreviate then s = getMS().Abbr(v) end
    return "-" .. s
end

RESOLVERS.power_type_string = function(elem, source)
    return getMS().SafeText(source:GetPowerTypeString())
end

-- ───── Shields & Heals ─────

RESOLVERS.absorb_amount = function(elem, source)
    local v = source:GetAbsorbAmount()
    if v == nil or v == 0 then return "" end
    return getMS().FormatNumber(v, elem.abbreviate)
end

RESOLVERS.overshield_amount = function(elem, source)
    local v = source:GetOvershieldAmount()
    if v == nil or v == 0 then return "" end
    return getMS().FormatNumber(v, elem.abbreviate)
end

RESOLVERS.heal_absorb_amount = function(elem, source)
    local v = source:GetHealAbsorbAmount()
    if v == nil or v == 0 then return "" end
    return getMS().FormatNumber(v, elem.abbreviate)
end

RESOLVERS.incoming_heal = function(elem, source)
    local v = source:GetIncomingHealTotal()
    if v == nil or v == 0 then return "" end
    return "+" .. getMS().FormatNumber(v, elem.abbreviate)
end

RESOLVERS.incoming_heal_mine = function(elem, source)
    local v = source:GetIncomingHealFromPlayer()
    if v == nil or v == 0 then return "" end
    return "+" .. getMS().FormatNumber(v, elem.abbreviate)
end

-- ───── Status / Threat / Range ─────

RESOLVERS.status_text = function(elem, source)
    if not source:IsConnected() then return "Offline" end
    if source:IsFeignDeath() then return "FD" end
    if source:IsGhost() then return "Ghost" end
    if source:IsDead() then return "Dead" end
    return ""
end

RESOLVERS.aggro_flag = function(elem, source)
    local s = source:GetAggroFlag() or 0
    if s == 0 then return ""
    elseif s == 1 then return "+"
    elseif s == 2 then return "++"
    elseif s == 3 then return "AGGRO"
    end
    return ""
end

RESOLVERS.threat_percent = function(elem, source)
    local pct = source:GetThreatPercent()
    if not pct or pct == 0 then return "" end
    return string.format("%.0f%%", pct)
end

RESOLVERS.range_text = function(elem, source)
    return source:IsInRange() and "" or "OOR"
end

-- ───── Group (meta) ─────

-- Groups concatenate other elements' resolved text. Phase B renders
-- groups as just their separator-joined item resolutions. (The real
-- implementation will deduplicate against per-item rendering once
-- live rendering ships; preview just shows the static concatenation.)
RESOLVERS.group = function(elem, source)
    -- groupItems is an array of typeKey strings.
    -- Each item resolves as if it were a standalone element (with
    -- default settings since group items don't have their own elem
    -- table). The group's separator joins them.
    if not elem.groupItems or #elem.groupItems == 0 then return "" end
    local parts = {}
    for _, typeKey in ipairs(elem.groupItems) do
        local itemResolver = RESOLVERS[typeKey]
        if itemResolver then
            -- Pass a minimal elem-like table for per-item formatting
            local itemElem = { contentType = typeKey, abbreviate = true, decimals = 0 }
            local v = itemResolver(itemElem, source)
            if v and v ~= "" then
                parts[#parts+1] = v
            end
        end
    end
    return table.concat(parts, elem.groupSeparator or " / ")
end

-- ============================================================
-- PUBLIC ENTRY POINT
-- ============================================================

-- Resolve(elem, source) -> string
function Resolver:Resolve(elem, source)
    if not elem or not elem.contentType then return "" end
    local fn = RESOLVERS[elem.contentType]
    if not fn then
        DF:Debug("TD", "Resolver: unknown contentType '%s' for elem id=%s",
            tostring(elem.contentType), tostring(elem.id))
        return ""
    end
    local ok, result = pcall(fn, elem, source)
    if not ok then
        DF:Debug("TD", "Resolver error for contentType '%s' (elem id=%s): %s",
            tostring(elem.contentType), tostring(elem.id), tostring(result))
        return ""
    end
    return result or ""
end

-- Expose for debugging
DF.TextDesigner.Resolver._RESOLVERS = RESOLVERS
