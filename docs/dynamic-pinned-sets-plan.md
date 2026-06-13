# Dynamic pinned sets (add / remove beyond the fixed 2)

Goal: let users add/remove pinned frame sets instead of the hardcoded 2, up to a
bounded `MAX_SETS`, with the active-set count surfaced for the secure-header perf cost.

## Why it's tractable
The pinned system is already index-driven: `CreateSetFrames(setIndex)`,
`self.headers[setIndex]`, and **all per-set config is nested on the `sets[i]` table**
(scale, position, border override, frameType, `auraDesignerPreset`/`textDesignerPreset`,
players, etc.). There is NO separate index-keyed override store for pinned sets — the
`pinned.N.*` strings in Options are just GUI control addressing, rebuilt per render.
ForEachDesignerRef + the redundancy cleanup already iterate `pairs(pinnedFrames.sets)`.

So removing a set = `table.remove(sets, i)` (config + preset refs go with it; higher
sets compact down). Runtime arrays are rebuilt by the existing `Reinitialize`.

## Constants / model
- `PinnedFrames.MAX_SETS = 5` (single tunable constant; perf-bounded — each *active*
  set is a live secure header re-evaluating on roster events).
- `local function NumSets(hlDB)` → `min(#hlDB.sets, MAX_SETS)`.
- Default profile still ships **2** sets (no behaviour change for existing users).

## Stages

### Stage 1 — Backend: generalize count + CRUD (PinnedFrames.lua)
- Add `MAX_SETS` + `NumSets()`.
- Replace runtime `for i = 1, 2` (ProcessAllSets, ComputeHiddenNames, Initialize apply
  loops, UpdateAllHeaders, LockAllForCombat/Restore, RefreshEnabledState, snapshot) →
  `for i = 1, NumSets(hlDB)`.
- Teardown/cleanup loops (Reinitialize, full hide) iterate `1, MAX_SETS` so stale frames
  beyond the current count are caught after a remove.
- `PinnedFrames:AddSet()` — guard `< MAX_SETS`; append a default set (mirror Config
  defaults, `enabled=false`, name `Pinned N`); `CreateSetFrames(n)` + `ApplyLayoutSettings`
  + `SetEnabled`. Combat-safe (defer via pending…). Returns new index.
- `PinnedFrames:RemoveSet(i)` — hide+nil set i's container/header/label/mover/bossHandler
  (secure frames can't be destroyed in combat → hide + drop DB entry, full teardown on the
  out-of-combat Reinitialize); `table.remove(sets, i)`; `Reinitialize()`. Combat-safe.

### Stage 2 — Editor UI: dynamic tabs + Add/Remove (Options.lua)
- Tab build loop `for i = 1, 2` (~2131) → `for i = 1, #sets`.
- "+ Add set" button after the tab row (disabled + greyed at `MAX_SETS`) → AddSet →
  RefreshCurrentPage → select new tab.
- Remove affordance: a "Remove set" button in the Setup panel (and/or `×` on the tab) →
  StaticPopup confirm → RemoveSet → clamp `persistedTab` → RefreshCurrentPage. Hidden when
  only 1 set remains.
- Active-count + cap chip near the tab strip; perf hint line (neutral ≤3, warning ≥ a
  threshold) — mirrors the mockup.
- Generalize the migration loop (`for i=1,2` at ~2131) → `for i=1,#sets`.
- Clamp `persistedTab` into `[1, #sets]`.

### Stage 3 — Iterate-all sites: AutoProfiles / snapshot / export
- Generalize remaining hardcoded `pf.sets[i]` under `for i=1,2` in AutoProfiles.lua
  (~2868, ~3107) and any snapshot/apply.
- Export/import copies the whole `pinnedFrames` table → variable length already carried;
  verify import of an N-set profile rebuilds N frames (Reinitialize on import).

### Stage 4 — Locale + CHANGELOG + verify
- Locale: "Add set", "Remove set", remove-confirm popup, active-count/cap + perf hint.
- CHANGELOG entry.
- Full syntax sweep; grep that no `for i = 1, 2` pinned loops remain; in-game test:
  add to MAX, remove middle, toggle, profile switch, /reload, combat add/remove deferral,
  export/import an N-set profile, boss set add/remove.

## Combat-safety notes
- AddSet creates a SecureGroupHeaderTemplate → out-of-combat only; defer with a pending
  flag consumed on PLAYER_REGEN_ENABLED (pattern already used by Initialize/Reinitialize).
- RemoveSet in combat: hide the frames + drop the DB entry now; the real secure-frame
  teardown happens on the next out-of-combat Reinitialize.
- The mover/secure position handlers already gate on combat.

## Migration
None required: existing profiles have 2 sets and keep working. New sets are created on
demand. `disableInPvP` default already seeded.
