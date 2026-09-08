# PR: Slice 6 — work priorities board

## Summary

This change extends Vault Tycoon's Godot 4.7.2 desktop prototype with a crew-wide work priorities board. Press **P** or choose **PRIORITIES** to view every resident against the four existing work categories: Dig, Haul, Craft, and Cook. Each cell holds OFF or a priority from 1 through 4, where 1 is highest. New residents start at priority 3 in every category.

The automatic scheduler now lets the resident with the strongest available category priority claim first, then applies its existing deterministic job-kind, distance, and job-ID tie-breaks for that resident. Resident ID resolves equal worker claims. This lets the player specialize the crew without issuing direct movement or individual job commands. Numeric changes affect the next job claim; switching a category OFF safely releases a resident already doing that category.

Maintenance-hatch supply and patch work remain absolute emergency overrides. An enabled Haul or Craft category responds regardless of whether its numeric value is 1 or 4, while OFF remains a real permission boundary and continues to produce the existing Haul/Craft blocker readout. Eating, sleeping, recreation, stress behavior, power allocation, oxygen, and every prior survival rule retain their established precedence.

## Focused Scope

- Canonical per-resident priorities for Dig, Haul, Craft, and Cook
- Five states per resident/category pair: OFF and numeric priorities 1–4
- Priority 1 as highest, priority 4 as lowest, and priority 3 as the uniform new-game default
- A complete resident-by-work board available from both **P** and the right-rail roster's **PRIORITIES [P]** control
- Fixed cell cycle `1 → 2 → 3 → 4 → OFF → 1`, with a visible legend and explicit close action
- Live eligible-resident counts for all four categories, with a missing-coverage warning
- Resident inspector controls that show the same numeric/OFF values as the crew board
- Ordinary job selection by personal work priority before the established deterministic fallbacks
- Immediate, reservation-safe release only when the active job's category is switched OFF
- Emergency hatch work above every numeric priority, while OFF Haul or Craft still blocks response
- Schema-one persistence for numeric priorities plus migration from legacy boolean work permissions
- Prior Slice 1–5 behavior, deterministic survival, and breach-warning modal regression remain in scope
- No skills, schedules, direct work orders, individual-job priorities, or broader management simulation

## Work Priority Contract

| Value | Meaning |
| --- | --- |
| `OFF` / `0` | This resident cannot claim work in the category |
| `1` | Highest enabled ordinary-work priority |
| `2` | Considered after that resident's priority-1 work |
| `3` | Normal new-game and legacy-enabled default |
| `4` | Lowest enabled ordinary-work priority |

The four board columns map to runtime jobs as follows:

| Board category | Jobs governed |
| --- | --- |
| **DIG** | Excavating designated rock |
| **HAUL** | Recovering rubble, supplying blueprints, and delivering emergency patch salvage |
| **CRAFT** | Assembling supplied fixtures and patching the maintenance hatch |
| **COOK** | Preparing meals at a powered Nutrient Station |

Available residents claim in this deterministic order:

1. A resident able to claim emergency hatch work before residents limited to ordinary work
2. The resident whose best available work has the lower numeric priority
3. Lower resident ID when those claim keys match

That resident chooses a job in this deterministic order:

1. Emergency hatch work before all ordinary work
2. Lower numeric work priority before higher numeric work priority
3. Existing fixed job-kind order: blueprint supply, fixture assembly, cooking, rubble hauling, then excavation
4. Shorter target distance
5. Lower job ID

OFF pairs never enter assignment. Equal values therefore reproduce the prior ordinary job-kind order, and the default priority-3 matrix preserves the existing first-playable route. Changing 1–4 while a resident is working does not interrupt that job; the new value applies at the next claim. Changing the active category to OFF releases the assignment immediately, clears its reservation, and safely restores or re-exposes any carried material for another eligible worker.

Emergency patch delivery and hatch patching are evaluated before the numeric board value and may preempt ordinary work, recreation, or a nonessential stress break. They still require Haul or Craft to be above OFF. Survival behavior remains autonomous: eating and sleeping are not board categories, and recreation remains autonomous self-care rather than work.

## Board Behavior

- **P** opens or closes the board; the right-rail roster's **PRIORITIES [P]** control opens it.
- Each row identifies one resident; each column identifies one of the four work categories.
- Clicking a cell advances only that resident/category through the fixed priority cycle.
- The displayed value and color update immediately and remain synchronized with the selected-resident inspector.
- A live **COVERAGE** summary counts eligible living residents by category and identifies categories with no eligible crew.
- **CLOSE**, **Esc**, or **P** dismisses the board.
- Opening, editing, or closing the board does not change simulation pause, speed, selected resident or fixture, or active map tool.
- The board captures its own pointer input so clicks do not place blueprints or map orders underneath it.
- Cells for deceased residents are noninteractive; living residents remain editable while the simulation is paused or running.
- The maintenance-hatch warning retains modal precedence, its focused Resume action, its exact 1× reset, and the speed-key acknowledgement guard.

## How To Review

Use Godot 4.7.2.

```bash
godot --editor --path .
```

Run the project with **F5**, select **BEGIN SHIFT**, then exercise this route:

1. Press **P**. Confirm the board fits the 1280×720 reference viewport, lists Ari, Bo, Cyra, and Dax against Dig, Haul, Craft, and Cook, and starts every living cell at 3. Confirm the legend says that 1 is highest and OFF disables work.
2. Reopen the board with **P** and the right-rail roster's **PRIORITIES [P]** control, then close it with **P**, **CLOSE**, and **Esc**. Confirm these actions preserve the current pause state, speed, selection, and map tool, and that clicks on the open board do not reach the map.
3. Click a default-3 cell repeatedly. Confirm it advances through 4, OFF, 1, 2, and back to 3, changes only the intended resident/category, and matches the selected-resident inspector. Turn a complete column OFF and confirm its coverage count reaches zero and raises the no-eligible-crew message.
4. Prepare reachable jobs in two categories. Give one category a lower number even when its target is farther away; confirm the lower numeric priority claims first. Give categories the same value and confirm the established job-kind, distance, and job-ID tie-breaks remain stable. Give two residents the same best claim and confirm lower resident ID claims first.
5. Change an enabled numeric priority while its resident works. Confirm the current job finishes and the new order applies to the next claim. Then switch the active category OFF and confirm the job releases immediately without losing salvage, duplicating work, or leaving a stale reservation.
6. Set a resident's Dig, Haul, or Cook category OFF in separate checks. Confirm that resident no longer claims the corresponding work and that **NO COOK ENABLED** appears only when every living resident has Cook OFF.
7. Leave Haul and Craft at priority 4, queue priority-1 ordinary work, and trigger the 60-second hatch warning. After resuming, confirm emergency patch delivery and patching preempt the ordinary work. Set every living resident's required category OFF and confirm the existing **BLOCKED · ENABLE HAUL** or **BLOCKED · ENABLE CRAFT** status appears instead.
8. Trigger the hatch warning while the priorities board is open. Confirm the warning retains focus, stays paused at 1×, and cannot be dismissed by the `1`, `2`, or `3` speed keys.
9. Save a mix of OFF and priorities 1–4, then load it. Confirm every cell round-trips and the loaded game remains deterministic and paused. Load a compatible schema-one save with only legacy boolean permissions; confirm `true` becomes 3 and `false` becomes OFF.
10. Load compatible saves with no work-priority data, active recreation, and in-flight breach response. Confirm missing priorities default to 3, console and emergency reservations reconcile safely, and no material is duplicated or lost.
11. Continue a managed wing through day seven and confirm numeric specialization does not change the established victory gates: at least one living resident, a sealed hatch, and oxygen at or above 15%.

## Automated Verification

Run the complete repository check:

```bash
scripts/check.sh
```

- Godot 4.7.2 completed the headless editor import and five-second boot without script or runtime errors.
- The core suite passes **34 cases / 617 assertions**; the focused work-priorities suite passes **9 cases / 237 assertions**; the mood/recreation suite passes **9 cases / 231 assertions**; and the breach-modal speed-key regression passes.
- `scripts/check.sh` runs all four suites between the import and boot checks.
- Three integrated cases in `tests/test_runner.gd` cover core scheduling, save compatibility, and HUD regressions. The focused `tests/test_work_priorities.gd` suite covers OFF and priorities 1–4; the uniform 4×4 defaults and fixed cycle; ordinary priority ordering plus intrinsic job-kind, distance, job-ID, and resident-ID ties; worker specialization; enabled-priority continuity; immediate OFF release and in-transit salvage refunds; urgent hatch override with OFF blockers; 4×4 HUD edits, deceased rows, keyboard focus trapping, and modal input behavior; numeric save round trips; legacy boolean and missing-field migration; and malformed-priority atomic rejection.

The existing suites remain responsible for scene boot, tools, construction, food, power, oxygen, breach timing and response, mood and recreation, save replacement atomicity, unmanaged loss, the player-order survival plan, and the managed day-seven win.

## Save and Compatibility Contract

- Save schema version remains **1**.
- Each resident writes a numeric `work_priorities` map with integer values from 0 through 4.
- New saves also retain the legacy boolean `work_allowed` map so earlier schema-one readers still receive enabled/disabled meaning.
- A legacy `work_allowed: true` value migrates to priority 3; `false` migrates to OFF.
- A missing numeric map migrates from the legacy booleans, defaulting any missing legacy category to priority 3.
- When a numeric map is present, it must contain all four categories; a partial map is malformed rather than silently mixed with defaults.
- When both maps are present, their enabled/OFF meaning must agree; a disagreement is rejected atomically.
- Malformed explicit priority maps or out-of-range/non-integral values are rejected before mutating the active wing.
- Saved emergency carriers remain valid only when their corresponding migrated Haul or Craft category is above OFF; an ineligible saved carrier is rejected before mutating the active wing. Existing compatible two-field emergency payloads retain their safe bind-or-refund migration.
- Prior optional breach, oxygen, power-disable, canonical mood, and recreation fields retain their Slice 1–5 migration behavior.
- Loading still returns the game in a paused state, resets transient UI selection, and reconstructs jobs and reservations from canonical state.

## Known Limitations

- Priorities rank four broad work categories only. There are no per-blueprint, per-recipe, per-fixture, or per-designation priorities.
- Residents have no work skills, aptitudes, passions, qualifications, equipment modifiers, or category-specific speed bonuses.
- There are no schedules, shifts, work zones, quotas, direct movement commands, forced jobs, or player-authored job queues.
- Numeric changes do not interrupt an enabled job already in progress; only OFF releases it immediately.
- Emergency hatch work has a fixed override and cannot be numerically demoted, though its required category can be turned OFF.
- Recreation, eating, and sleeping remain autonomous and do not appear on the work board.
- The board targets the fixed-density 1280×720 keyboard-and-mouse interface; there is no mobile, touch, handheld-safe-area, or small-screen adaptation.
- Placeholder geometry, colors, resident markers, and controls remain; final art, animation, sound, and effects are outside this slice.

## Next Steps

1. Record a complete interactive Linux day-seven smoke using distinct resident specialties and an emergency override.
2. Tune default specialization examples only after observing full-run construction, hauling, cooking, mood, and hatch contention.
3. Consider schedules, work skills, or narrower job controls only as separately scoped slices.

Surface play, caravans, factions, research, mods, multiplayer, IAP, ads, analytics, store packaging, final art/audio, and mobile export remain out of scope. So do relationships, social simulation, traits, memories, schedules, direct orders, work skills, work zones, job bills, raiders, enemies, weapons, combat, repeated/procedural incidents, spatial gas or pressure zones, oxygen networks, multiple-room sealing, and a sealed-door graph.
