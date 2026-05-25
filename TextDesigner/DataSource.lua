local addonName, DF = ...

-- ============================================================
-- TEXT DESIGNER — DATA SOURCE
-- Abstraction layer between the Resolver and the underlying
-- data (real unit-frame state OR synthetic mock values).
-- Both factories return an object implementing the same getter
-- interface, so the Resolver is phase-agnostic.
-- ============================================================

DF.TextDesigner = DF.TextDesigner or {}
local DataSource = {}
DF.TextDesigner.DataSource = DataSource

local MS = nil  -- resolved lazily; MidnightSafe loads before Resolver but file load order is TextDesigner→MidnightSafe→DataSource

local function getMS()
    if not MS then MS = DF.TextDesigner.MidnightSafe end
    return MS
end

-- ============================================================
-- MOCK DATA — synthetic values for the preview
-- ============================================================

local MOCK_DATA = {
    -- Identity
    name             = "Danders",
    classToken       = "SHAMAN",
    classLocalized   = "Shaman",
    level            = 80,
    race             = "Draenei",
    raceLocalized    = "Draenei",
    faction          = "Alliance",
    groupNumber      = 2,
    -- Health
    hpCurrent        = 287456,
    hpMax            = 471140,
    hpPercent        = 61,
    hpDeficit        = 183684,
    hpMaxReductionPct = 0,
    -- Power
    powerCurrent     = 154000,
    powerMax         = 278460,
    powerPercent     = 55,
    powerDeficit     = 124460,
    powerTypeToken   = "MANA",
    powerTypeString  = "Mana",
    -- Shields & Heals
    absorbAmount     = 25000,
    overshieldAmount = 0,
    healAbsorbAmount = 0,
    incomingHealTotal = 12000,
    incomingHealFromPlayer = 8000,
    -- Status / Threat / Range
    isDead           = false,
    isGhost          = false,
    isConnected      = true,
    isFeignDeath     = false,
    aggroFlag        = 0,
    threatPercent    = 0,
    isInRange        = true,
}

-- ============================================================
-- MOCK FACTORY
-- Returns a source that reads from MOCK_DATA. Used for the preview.
-- ============================================================

local mockSourceInstance  -- singleton — mock data is shared

local MockSource = {}
MockSource.__index = MockSource

function MockSource:_isMock() return true end

function MockSource:GetName() return MOCK_DATA.name end
function MockSource:GetClassToken() return MOCK_DATA.classToken end
function MockSource:GetClassLocalized() return MOCK_DATA.classLocalized end
function MockSource:GetLevel() return MOCK_DATA.level end
function MockSource:GetRace() return MOCK_DATA.raceLocalized end
function MockSource:GetFaction() return MOCK_DATA.faction end
function MockSource:GetGroupNumber() return MOCK_DATA.groupNumber end

function MockSource:GetHPCurrent() return MOCK_DATA.hpCurrent end
function MockSource:GetHPMax() return MOCK_DATA.hpMax end
function MockSource:GetHPPercent() return MOCK_DATA.hpPercent end
function MockSource:GetHPDeficit() return MOCK_DATA.hpDeficit end
function MockSource:GetHPMaxReductionPct() return MOCK_DATA.hpMaxReductionPct end

function MockSource:GetPowerCurrent() return MOCK_DATA.powerCurrent end
function MockSource:GetPowerMax() return MOCK_DATA.powerMax end
function MockSource:GetPowerPercent() return MOCK_DATA.powerPercent end
function MockSource:GetPowerDeficit() return MOCK_DATA.powerDeficit end
function MockSource:GetPowerTypeToken() return MOCK_DATA.powerTypeToken end
function MockSource:GetPowerTypeString() return MOCK_DATA.powerTypeString end

function MockSource:GetAbsorbAmount() return MOCK_DATA.absorbAmount end
function MockSource:GetOvershieldAmount() return MOCK_DATA.overshieldAmount end
function MockSource:GetHealAbsorbAmount() return MOCK_DATA.healAbsorbAmount end
function MockSource:GetIncomingHealTotal() return MOCK_DATA.incomingHealTotal end
function MockSource:GetIncomingHealFromPlayer() return MOCK_DATA.incomingHealFromPlayer end

function MockSource:IsDead() return MOCK_DATA.isDead end
function MockSource:IsGhost() return MOCK_DATA.isGhost end
function MockSource:IsConnected() return MOCK_DATA.isConnected end
function MockSource:IsFeignDeath() return MOCK_DATA.isFeignDeath end
function MockSource:GetAggroFlag() return MOCK_DATA.aggroFlag end
function MockSource:GetThreatPercent() return MOCK_DATA.threatPercent end
function MockSource:IsInRange() return MOCK_DATA.isInRange end

function DataSource.Mock()
    if not mockSourceInstance then
        mockSourceInstance = setmetatable({}, MockSource)
    end
    return mockSourceInstance
end

DataSource.MOCK_DATA = MOCK_DATA  -- expose so Preview can read it for chrome rendering

-- ============================================================
-- LIVE FACTORY
-- Returns a source bound to a real DF frame.unit. Reads from
-- cached frame state where available, falls back to direct API.
-- Note: this is fully implemented now so Phase C plugs in cleanly,
-- but isn't yet consumed by the preview pipeline.
-- ============================================================

local LiveSource = {}
LiveSource.__index = LiveSource

function LiveSource:_isMock() return false end

function LiveSource:GetName()
    if DF.GetUnitName then return DF:GetUnitName(self.unit) end
    return UnitName(self.unit) or ""
end

function LiveSource:GetClassToken()
    local _, token = UnitClass(self.unit)
    return token or "WARRIOR"  -- fallback so RAID_CLASS_COLORS lookup never returns nil
end

function LiveSource:GetClassLocalized()
    return UnitClass(self.unit) or ""
end

function LiveSource:GetLevel()
    local lvl = UnitLevel(self.unit)
    if getMS().IsSecret(lvl) then return "??" end
    if not lvl or lvl <= 0 then return "??" end
    return lvl
end

function LiveSource:GetRace()
    return UnitRace(self.unit) or ""
end

function LiveSource:GetFaction()
    return UnitFactionGroup(self.unit) or ""
end

function LiveSource:GetGroupNumber()
    local idx = UnitInRaid(self.unit)
    if not idx then return nil end
    local _, _, subgroup = GetRaidRosterInfo(idx)
    if getMS().IsSecret(subgroup) then return nil end
    return subgroup
end

function LiveSource:GetHPCurrent()
    return UnitHealth(self.unit)
end

function LiveSource:GetHPMax()
    return UnitHealthMax(self.unit)
end

function LiveSource:GetHPPercent()
    if _G.UnitHealthPercent then
        return UnitHealthPercent(self.unit, true, getMS().ScaleTo100)
    end
    return nil
end

function LiveSource:GetHPDeficit()
    if _G.UnitHealthMissing then
        return UnitHealthMissing(self.unit)
    end
    return nil
end

function LiveSource:GetHPMaxReductionPct()
    if _G.GetUnitTotalModifiedMaxHealthPercent then
        return GetUnitTotalModifiedMaxHealthPercent(self.unit)
    end
    return 0
end

function LiveSource:GetPowerCurrent()
    return UnitPower(self.unit)
end

function LiveSource:GetPowerMax()
    return UnitPowerMax(self.unit)
end

function LiveSource:GetPowerPercent()
    if _G.UnitPowerPercent then
        return UnitPowerPercent(self.unit, nil, false, getMS().ScaleTo100)
    end
    return nil
end

function LiveSource:GetPowerDeficit()
    if _G.UnitPowerMissing then
        return UnitPowerMissing(self.unit)
    end
    return nil
end

function LiveSource:GetPowerTypeToken()
    local _, token = UnitPowerType(self.unit)
    return token or "MANA"
end

function LiveSource:GetPowerTypeString()
    local _, token = UnitPowerType(self.unit)
    return _G["POWER_TYPE_" .. (token or "MANA")] or token or ""
end

function LiveSource:GetAbsorbAmount()
    return UnitGetTotalAbsorbs(self.unit) or 0
end

function LiveSource:GetOvershieldAmount()
    -- Uses the calculator's clamp-mode trick. Requires the frame's
    -- absorb calculator to be populated, which UpdateAbsorb does
    -- before our LiveHooks fire in Phase C.
    local calc = self.frame and self.frame.absorbCalculator
    if not calc or not _G.UnitGetDetailedHealPrediction then return 0 end
    pcall(calc.SetDamageAbsorbClampMode, calc, 1)
    pcall(UnitGetDetailedHealPrediction, self.unit, "player", calc)
    local _, excess = pcall(calc.GetDamageAbsorbs, calc)
    return excess or 0
end

function LiveSource:GetHealAbsorbAmount()
    return UnitGetTotalHealAbsorbs(self.unit) or 0
end

function LiveSource:GetIncomingHealTotal()
    -- Prefer cached value from UpdateHealPrediction (Phase C stash)
    if self.frame and self.frame.dfTotalHeals ~= nil then
        return self.frame.dfTotalHeals
    end
    return UnitGetIncomingHeals(self.unit) or 0
end

function LiveSource:GetIncomingHealFromPlayer()
    if self.frame and self.frame.dfMyHeals ~= nil then
        return self.frame.dfMyHeals
    end
    return UnitGetIncomingHeals(self.unit, "player") or 0
end

function LiveSource:IsDead()
    return UnitIsDead(self.unit) or false
end

function LiveSource:IsGhost()
    return UnitIsGhost(self.unit) or false
end

function LiveSource:IsConnected()
    return UnitIsConnected(self.unit)
end

function LiveSource:IsFeignDeath()
    return UnitIsFeignDeath(self.unit) or false
end

function LiveSource:GetAggroFlag()
    return UnitThreatSituation(self.unit) or 0
end

function LiveSource:GetThreatPercent()
    local _, _, pct = UnitDetailedThreatSituation("player", self.unit)
    return pct
end

function LiveSource:IsInRange()
    -- frame.dfInRange is populated by the Range module. May be secret —
    -- guard via MidnightSafe.
    if self.frame and self.frame.dfInRange ~= nil then
        return getMS().SafeBoolean(self.frame.dfInRange, true)
    end
    -- Fallback: direct API call (also potentially secret)
    return getMS().SafeBoolean(UnitInRange(self.unit), true)
end

function DataSource.Live(frame)
    local instance = setmetatable({}, LiveSource)
    instance.frame = frame
    instance.unit = frame and frame.unit or nil
    return instance
end
