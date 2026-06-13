# Designer Presets (Aura Designer + Text Designer) — Plan

> Status: **planned, not started.** Standalone feature, its own PR. Best done
> *after* the Pinned Frames rework lands and the fork syncs. Closes the descoped
> aura side of feature requests **#2 (part 2)** and **#27** (pinned-specific auras),
> and is independently valuable (different aura/text setups per content type).

## Goal

Let users build **named presets** of an Aura Designer (AD) / Text Designer (TD)
configuration, then let each *consumer* (party frames, raid frames, arena, and
**each pinned set**) simply **pick which preset to use**. No parallel editor —
the user reuses the AD/TD they already know and just assigns a preset.

From the user's point of view a pinned set is one dropdown:
> Auras: `[ Tank Focus ▾ ]`   Text: `[ Default ▾ ]`

## Current architecture (what we build on)

- AD/TD config is stored **per mode**: `db.party.auraDesigner`, `db.raid.auraDesigner`
  (same for `textDesigner`). `Config.lua` ~2391 / ~3888.
- **Every** render read funnels through `DF:GetFrameDB(frame)` then `.auraDesigner` /
  `.textDesigner` — ~6 AD reads (Engine 374/854/1079, AuraAdapter 481) + ~3 TD reads.
  `GetFrameDB` picks party-vs-raid by the frame's `isRaidFrame` flag.
- Editors bind to `DF:GetDB(GUI.SelectedMode).<designer>` (AD Options 340/365, TD 2583).

So presets slot in at exactly two narrow points: **how config is resolved per
frame**, and **what the editor edits**. The render/spec code does not change.

## AD config is already spec-scoped (presets nest *above* spec)

The AD config contains the spec dimension **inside it**:

```
auraDesigner = {
    enabled, previewScale, soundEnabled, defaults = {…},
    spec = "auto",                         -- "auto" (follow current spec) or a fixed spec
    auras        = { [specKey] = { [auraName] = cfg } },   -- per-spec
    layoutGroups = { [specKey] = {…} },                    -- per-spec
    nextLayoutGroupID,
}
```

The engine resolves spec *inside* whatever config it's handed:
`spec = ResolveSpec(adDB)` → `adDB.auras[spec]` (Engine 377/396, 860/871, 1083/1086).

**A preset is a whole AD config**, so it already contains its own per-spec
`auras`/`layoutGroups` + the `spec` mode. Presets and spec are therefore
**orthogonal and nested**, not competing knobs:

```
Preset "Tank Focus"
 ├─ spec = "auto"
 ├─ defaults / preview / sound
 ├─ auras[Holy] / auras[Disc] / …
 └─ layoutGroups[…] per spec
```

Hand the engine a preset as `adDB` and the per-spec logic runs on the preset's
data — **zero change to the spec code.** The preset swap happens one level up.

Mental model (use in UI copy):
- **Spec** = "what shows for *each* of my specs" — handled *within* a setup, usually `auto`.
- **Preset** = "a whole named setup" (Tank Focus vs Healer Auras vs Minimal).

So presets are for *fundamentally different* setups, not for spec variation.

## Data model

Presets are the **only** storage of designer configs; consumers store a name.

```
profile.auraDesignerPresets = { ["Party"]={…}, ["Raid"]={…}, ["Tank Focus"]={…} }
profile.textDesignerPresets = { ["Party"]={…}, ["Raid"]={…} }

db.party.auraDesignerPreset = "Party"      -- main frames reference a name
db.raid.auraDesignerPreset  = "Raid"
set.auraDesignerPreset       = "Tank Focus" -- pinned set references a name (+ textDesignerPreset)
```

Storing only the **name** (never a duplicated table) avoids the SavedVariables
"shared table reference becomes two copies on reload" trap — one canonical table
per preset.

## Resolution (the funnel)

Add one resolver per designer and point the ~9 reads at it:

```
DF:ResolveAuraDesigner(frame)   -- pinned set's preset → else the frame mode's preset → "Default"
DF:ResolveTextDesigner(frame)
```

- For **pinned** frames, "which mode" is the **Based-on** mode (consistent with the
  size/border stamps); the per-set preset overrides it. Same idea as the
  `dfPinned*` stamps, but resolving a *named table* instead of values.
- Keep a non-deletable `"Default"` as the ultimate fallback.

## Editor changes (AD + TD)

Add a **preset bar** at the top that *wraps* the existing spec selector:

```
Aura Designer
  Preset:  [ Tank Focus ▾ ]   [New] [Duplicate] [Rename] [Delete]
  Spec:    [ Holy ▾ ]                     ← existing per-spec view, unchanged
  ─────────────────────────────────────
  (auras / layout groups for that preset + spec)
```

The editor edits `presets[selectedPreset]` instead of `db[mode].<designer>`.
Everything else in the editor is untouched. Editing a preset updates **every**
consumer using it — that's the point.

## Pinned integration (the payoff)

Small "Auras & Text" group on the pinned page:
- **Auras: [preset ▾]** → `set.auraDesignerPreset`
- **Text: [preset ▾]** → `set.textDesignerPreset`
- **Show Auras** / **Show Text** master on/off (clean health-only highlight)
- First dropdown entry = **"Inherit (follow Based-on)"** so doing nothing keeps
  current behaviour.

Spec behaviour rides along inside the chosen preset (auto-adapts or fixed) — the
user never sees a spec×preset matrix.

## Migration (lossless)

Walk **all** profiles (mirror `MigratePinnedMatchMode`'s all-profiles loop; do NOT
gate on the login-active profile — that was the TD-migration bug):
- Move `db.party/raid.<designer>` into `presets["Party"]` / `presets["Raid"]`,
  set the consumer's `<designer>Preset` name, clear the inline table.
- The entire per-spec `auras`/`layoutGroups` table carries across untouched — no
  separate per-spec migration. The `spec` mode comes with it.
- New profiles seed a `"Default"` preset.

## Gotchas / interactions

- **Auto-layout override gotcha** (the "swap whole table in place or designer pages
  freeze" note): presets **simplify** this — a raid auto-layout overrides the preset
  **name** (a plain string), not a whole table. The in-place-swap hazard disappears.
- **Delete / rename an in-use preset:** delete must reassign consumers to `"Default"`;
  rename must update all references. Keep `"Default"` non-deletable.
- **Combat:** preset selection is a plain value write — safe; no secure-frame work.

## Phasing

1. **Backend** — preset libraries + resolvers + swap the ~9 read points + migration.
   *No UX change* (party/raid auto-map to "Party"/"Raid" presets; behaviour identical).
   Medium, low risk (bounded reads).
2. **Editor preset bar** — selector + New/Duplicate/Rename/Delete (wraps the spec view). Medium.
3. **Consumer selectors** — party/raid/arena + **pinned** dropdowns + Show toggles. Small.

## Open decision (defer to v1+)

Per-consumer **spec-mode override** on top of a preset (e.g. same auras but party
fixed-to-Holy while pinned is `auto`). Rare; would be a tiny extra control. Leave
out of v1 — spec is already solved inside each preset.
