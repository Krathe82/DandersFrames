local addonName, DF = ...

-- ============================================================
-- TEXT DESIGNER — MIDNIGHT-SAFE WRAPPERS
-- Centralized secret-value handling for the TD render pipeline.
-- All resolvers route formatting through this module so the
-- "where do secrets need handling" knowledge stays in one place.
-- ============================================================

DF.TextDesigner = DF.TextDesigner or {}
local MS = {}
DF.TextDesigner.MidnightSafe = MS

-- File-scope caches for the Midnight sentinel APIs. These may not
-- exist on older clients (we still want TD to load and degrade
-- gracefully, even though it's alpha-gated to Midnight).
local issecretvalue = _G.issecretvalue
local type, tostring = type, tostring
local format = string.format
-- AbbreviateNumbers preferred (no space: "287k", "1.2m"); falls back to
-- AbbreviateLargeNumbers (space-padded: "287 K") on older clients. Both
-- are secret-safe in Midnight per Cell's reference implementation.
local AbbreviateNumbers = _G.AbbreviateNumbers or _G.AbbreviateLargeNumbers or tostring
local AbbreviateLargeNumbers = _G.AbbreviateLargeNumbers or tostring
local TruncateWhenZero = (_G.C_StringUtil and _G.C_StringUtil.TruncateWhenZero) or AbbreviateNumbers
local RoundToNearestString = (_G.C_StringUtil and _G.C_StringUtil.RoundToNearestString) or function(v) return tostring(v) end

-- The Midnight curve constant for percent calls. Falls back to `true`
-- (which UnitHealthPercent etc. accept as "use default curve") if
-- CurveConstants is missing.
MS.ScaleTo100 = _G.CurveConstants and _G.CurveConstants.ScaleTo100 or true

-- Returns true if v is a Midnight secret value.
-- `issecretvalue` is Blizzard's sentinel API — it accepts any input
-- (including secrets, userdata, nil) without throwing. Safe to call raw.
function MS.IsSecret(v)
    if not issecretvalue then return false end
    return issecretvalue(v) and true or false
end

-- Coerces any value to a string safely renderable via SetText.
-- - Strings/numbers pass through unchanged (secret or not).
-- - Booleans become "true"/"false".
-- - nil becomes "".
-- - userdata/tables become "" (we never want to display those).
function MS.SafeText(v)
    local t = type(v)
    if t == "string" or t == "number" then return v end
    if t == "boolean" then return v and "true" or "false" end
    return ""
end

-- AbbreviateNumbers wrapper that accepts secrets natively.
-- Returns a string ready for SetText (e.g. "287k"), or "" if v is nil.
-- Matches the legacy DF format (no space between digits and suffix).
function MS.Abbr(v)
    if v == nil then return "" end
    return AbbreviateNumbers(v)
end

-- TruncateWhenZero wrapper that returns "" instead of nil on zero
-- (TruncateWhenZero returns nil for zero values, and SetText errors
-- on nil — so we coerce here).
function MS.Truncate(v)
    if v == nil then return "" end
    local result = TruncateWhenZero(v)
    return result or ""
end

-- Format a (possibly secret) percent as a display string.
-- If the value is secret, uses RoundToNearestString (secret-safe).
-- If not secret, uses standard formatting with decimals.
function MS.PctText(pct, decimals)
    if pct == nil then return "" end
    decimals = decimals or 0
    if MS.IsSecret(pct) then
        -- Secret path — must use C_StringUtil
        local precision = decimals == 0 and 1 or (10 ^ -decimals)
        return RoundToNearestString(pct, precision) .. "%"
    end
    -- Non-secret path — standard format
    return format("%." .. decimals .. "f%%", pct)
end

-- Format a number as a display string respecting "abbreviate" setting.
-- If abbreviate is true, returns Abbr(v); otherwise SafeText(v).
function MS.FormatNumber(v, abbreviate)
    if v == nil then return "" end
    if abbreviate then return MS.Abbr(v) end
    return MS.SafeText(v)
end

-- Wraps issecretvalue around a boolean read.
-- Use this for UnitInRange which can return a secret boolean.
-- Returns the boolean if safe to read, OR the fallbackValue
-- (default false) if secret.
function MS.SafeBoolean(v, fallbackValue)
    if v == nil then return fallbackValue or false end
    if type(v) == "boolean" and not MS.IsSecret(v) then return v end
    -- Secret or non-boolean — fall back
    return fallbackValue or false
end
