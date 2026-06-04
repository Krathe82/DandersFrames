local addonName, DF = ...

-- ============================================================
-- TEXT DESIGNER — LEGACY MIGRATION
-- One-time conversion of the addon's built-in name / health / status
-- text settings into Text Designer elements. Runs once per mode on
-- login (idempotent via a per-mode flag) and can be re-run on demand
-- from the Global tab's "Import Current Text Settings" button.
-- ============================================================

-- Release-channel gate: TD is alpha-only, mirror the other TD files so we
-- don't register the migration function on release builds.
if DF.RELEASE_CHANNEL == "release" then return end

local ipairs, pairs, type = ipairs, pairs, type

-- Deep-copy a color table so migrated elements don't share refs with the
-- legacy db (editing one mustn't mutate the other). Falls back to white.
local function copyColor(c)
    if type(c) ~= "table" then return {r = 1, g = 1, b = 1, a = 1} end
    return {r = c.r or 1, g = c.g or 1, b = c.b or 1, a = c.a or 1}
end

-- The override flags every migrated element carries. Only the keys that
-- resolveAppearance (Render.lua) actually reads are listed — anything else
-- would be inert. With these all true, each element renders exactly the
-- legacy appearance instead of inheriting globalDefaults.
local function appearanceOverrides()
    return {
        font          = true,
        fontSize      = true,
        outline       = true,
        color         = true,
        useClassColor = true,
    }
end

-- ============================================================
-- PER-MODE BUILD
-- ============================================================

-- Builds the elements array for one mode's legacy settings. `tdDB` is the
-- mode's db.textDesigner; the nextElementID counter on it is used + bumped
-- the same way the picker does so future manual adds keep unique ids.
local function buildElements(db, tdDB)
    tdDB.nextElementID = tdDB.nextElementID or 1
    local function nextID()
        local id = tdDB.nextElementID
        tdDB.nextElementID = id + 1
        return id
    end

    local elements = {}

    -- ── NAME ─────────────────────────────────────────────────
    elements[#elements + 1] = {
        id            = nextID(),
        contentType   = "name",
        enabled       = true,
        label         = "",
        anchor        = db.nameTextAnchor,
        offsetX       = db.nameTextX,
        offsetY       = db.nameTextY,
        color         = copyColor(db.nameTextColor),
        useClassColor = db.nameTextUseClassColor,
        outline       = db.nameTextOutline,
        font          = db.nameFont,
        fontSize      = db.nameFontSize,
        nameLength    = db.nameTextLength,
        truncateMode  = db.nameTextTruncateMode,
        overrides     = appearanceOverrides(),
    }

    -- ── HEALTH ───────────────────────────────────────────────
    -- Common appearance/position carried by the health element (or the
    -- group element, for composite formats — the group renders as one
    -- FontString so it owns the font/size/outline/color/anchor/offset).
    local healthFormat = db.healthTextFormat or "PERCENT"
    -- Color is re-copied per element (in newHealthElem) so a group + its
    -- siblings never share the same color ref.
    local healthCommon = {
        anchor        = db.healthTextAnchor,
        offsetX       = db.healthTextX,
        offsetY       = db.healthTextY,
        useClassColor = db.healthTextUseClassColor,
        outline       = db.healthTextOutline,
        font          = db.healthFont,
        fontSize      = db.healthFontSize,
    }
    local function newHealthElem(extra)
        local e = {
            id            = nextID(),
            enabled       = true,
            label         = "",
            anchor        = healthCommon.anchor,
            offsetX       = healthCommon.offsetX,
            offsetY       = healthCommon.offsetY,
            color         = copyColor(db.healthTextColor),
            useClassColor = healthCommon.useClassColor,
            outline       = healthCommon.outline,
            font          = healthCommon.font,
            fontSize      = healthCommon.fontSize,
            overrides     = appearanceOverrides(),
        }
        for k, v in pairs(extra) do e[k] = v end
        return e
    end

    if healthFormat == "PERCENT" then
        elements[#elements + 1] = newHealthElem({
            contentType = "hp_percent",
            decimals    = 0,
            hidePercent = db.healthTextHidePercent,
        })
    elseif healthFormat == "CURRENT" then
        elements[#elements + 1] = newHealthElem({
            contentType  = "hp_current",
            abbreviate   = db.healthTextAbbreviate,
            hideWhenZero = true,
        })
    elseif healthFormat == "DEFICIT" then
        elements[#elements + 1] = newHealthElem({
            contentType  = "hp_deficit",
            abbreviate   = db.healthTextAbbreviate,
            hideWhenZero = true,
        })
    elseif healthFormat == "CURRENTMAX" or healthFormat == "CURRENT_MAX" then
        elements[#elements + 1] = newHealthElem({
            contentType    = "group",
            groupSeparator = " / ",
            groupItems     = {
                { contentType = "hp_current", abbreviate = db.healthTextAbbreviate, hideWhenZero = false },
                { contentType = "hp_max",     abbreviate = db.healthTextAbbreviate },
            },
        })
    elseif healthFormat == "CURRENT_PERCENT" then
        elements[#elements + 1] = newHealthElem({
            contentType    = "group",
            groupSeparator = " ",
            groupItems     = {
                { contentType = "hp_current", abbreviate = db.healthTextAbbreviate },
                { contentType = "hp_percent", decimals = 0 },
            },
        })
    else
        -- Unknown / unsupported legacy format → safest default.
        elements[#elements + 1] = newHealthElem({
            contentType = "hp_percent",
            decimals    = 0,
            hidePercent = db.healthTextHidePercent,
        })
    end

    -- ── STATUS (Dead / Offline / Ghost) ──────────────────────
    if db.statusTextEnabled ~= false then
        elements[#elements + 1] = {
            id            = nextID(),
            contentType   = "status_text",
            enabled       = true,
            label         = "",
            anchor        = db.statusTextAnchor,
            offsetX       = db.statusTextX,
            offsetY       = db.statusTextY,
            color         = copyColor(db.statusTextColor),
            outline       = db.statusTextOutline,
            font          = db.statusTextFont,
            fontSize      = db.statusTextFontSize,
            overrides     = appearanceOverrides(),
        }
    end

    return elements
end

-- ============================================================
-- PUBLIC ENTRY POINT
-- ============================================================

-- Converts the legacy built-in text settings into Text Designer elements
-- for BOTH modes. When `force` is falsy each mode is skipped if it has
-- already been migrated or already has TD elements (don't clobber a
-- user-built setup). When `force` is true the elements array is rebuilt
-- from the current legacy settings, overwriting whatever was there.
function DF:MigrateTextDesignerFromLegacy(force)
    if not DF.db then
        DF:Debug("TD", "Migrate: DF.db not ready, aborting")
        return
    end

    for _, mode in ipairs({ "party", "raid" }) do
        local db = DF:GetDB(mode)
        if not db then
            DF:Debug("TD", "Migrate: no db for mode=%s", mode)
        else
            -- Mirror Options' init so every TD field the editor expects exists.
            local tdDB = DF.TextDesigner:EnsureDB(db)

            local already = tdDB.migratedFromLegacy == true
                or (tdDB.elements and #tdDB.elements > 0)

            if not force and already then
                DF:Debug("TD", "Migrate: skipping mode=%s (already migrated or has elements)", mode)
            else
                tdDB.elements = buildElements(db, tdDB)

                -- Full switch: turn the system on and hide the built-in widgets
                -- so only the migrated TD elements show.
                tdDB.enabled = true
                tdDB.hideLegacyText = true
                tdDB.migratedFromLegacy = true

                DF:Debug("TD", "Migrate: mode=%s built %d element(s) (force=%s)",
                    mode, #tdDB.elements, tostring(force))
            end
        end
    end

    -- Refresh the preview (if the GUI is open) and every live frame so the
    -- change is visible immediately.
    if DF.TextDesigner.Preview and DF.TextDesigner.Preview.RefreshAll then
        DF.TextDesigner.Preview:RefreshAll()
    end
    if DF.UpdateAllFrames then
        DF:UpdateAllFrames()
    end
end

DF:Debug("TD", "Migration module loaded (channel=%s)", tostring(DF.RELEASE_CHANNEL))
