# PR: Slice 7 — first-session playability polish

## Summary

This change tunes Vault Tycoon's existing Godot 4.7.x desktop prototype so a competent first session can reach a managed day-seven victory without perfect play. The starting kit now provides 12 meals, 4 raw food, and 48 salvage while retaining 100% starting oxygen, the 2-power emergency core, one Lumen, and one Salvage Bay. Expansion remains necessary, and an untouched wing remains designed to fail.

The in-game checklist now follows the actual survival path: connected excavation, bunks, added power, powered food production, powered air recycling, and preparation for the maintenance-hatch patch. **HELP** in the bottom toolbar reopens that checklist and pauses the simulation while it is visible. Closing Help restores the prior running or paused state. Recreation and numeric work specialization are clearly marked as optional support tools rather than victory requirements.

This is a polish and balance slice, not a new major system. It preserves the sealed wing, aggregate oxygen, deterministic breach, fixed power shedding, mood/recreation, crew priorities, saves, and day-seven outcome rules established in Slices 1–6.

## Focused scope

- More forgiving starting food and salvage headroom
- A documented, achievable critical path through day seven
- A reopenable in-game Help/checklist surface
- Clearer Select, Dig, Cancel, build, power, and priority guidance
- Persistent active-tool help after transient feedback expires
- Explicit day-seven messaging when the hatch or oxygen still blocks victory
- A real-order managed smoke route and the existing unmanaged-failure guard
- Current README and review notes for controls and gameplay constants
- No new major gameplay system, store packaging, or release work

## Starting kit and economy contract

| Resource or fixture | New-wing value |
| --- | ---: |
| Meals | 12 |
| Raw food | 4 |
| Salvage | 48 |
| Vault oxygen | 100% |
| Emergency Core | 2 power |
| Lumen | Built; 1-power demand |
| Salvage Bay | Built |
| Salvage per excavated tile | 3 after rubble is hauled |

The checklist asks for at least 12 connected excavations. Their 36 recoverable salvage brings the route's total pool to 84.

| Critical-route spend | Salvage |
| --- | ---: |
| Two Bunks | 16 |
| One Charge Node | 18 |
| One Grow Tray | 12 |
| One Nutrient Station | 10 |
| One Air Recycler | 14 |
| Maintenance-hatch patch | 4 |
| **Total** | **74** |

That leaves 10 salvage beyond the complete critical route, enough to absorb one unnecessary small fixture or another minor first-session mistake. A 15-tile expansion yields 45 salvage and a total pool of 93, leaving 7 salvage after adding the optional 8-salvage Rec Console and completing the hatch patch.

Blueprint placement does not spend salvage immediately. Residents with Haul enabled supply queued fixtures as material becomes available, then residents with Craft enabled assemble them. Players must still recover excavated rubble and avoid committing the 4 salvage reserved for the hatch response.

## First-session route

1. Start the shift and activate **DIG [E]**.
2. Click or drag across at least 12 rock tiles connected to carved floor, directly or through an adjacent designation chain.
3. Let eligible residents excavate those tiles and haul the resulting rubble to a Salvage Bay.
4. Assemble at least two Bunks.
5. Assemble one Charge Node, raising total supply from 2 to 9 power.
6. Assemble and power one Air Recycler.
7. Assemble and power one Grow Tray and one Nutrient Station, with Cook above OFF for at least one living resident.
8. Keep 4 salvage available and keep Haul and Craft above OFF for at least one living resident before the hatch warning.
9. Resume the urgent response at the warning. An eligible hauler delivers the patch material and an eligible crafter completes the 8-second seal reinforcement.
10. Finish seven full days with at least one living resident, a sealed hatch, and oxygen at or above 15%.

The Rec Console is optional. The work priorities board is also optional: the default priority-3 matrix can complete the route, while **P** lets players specialize the crew.

## Help and checklist behavior

- The opening stabilization checklist appears before the first shift.
- **HELP** in the bottom toolbar reopens it during play; Help has no keyboard shortcut.
- The simulation pauses behind the reopened overlay. **CLOSE** or **Esc** restores the exact prior running or paused state.
- The full-screen overlay blocks map clicks and held camera input, and keyboard focus remains trapped on its visible actions.
- The checklist tracks 12 connected excavations, two or more Bunks, a Charge Node, a powered Air Recycler, a powered Grow Tray and Nutrient Station with Cook coverage, hatch-response salvage and Haul/Craft coverage, a sealed hatch, and the final day-seven oxygen gate.
- Rec Console and **P** work-priority guidance are visually identified as optional.
- Right-click and **Esc** are described as returning to Select; **X** is described as the Cancel tool.
- Active-tool guidance returns after temporary success, blocker, and warning messages expire.
- If day seven completes before the final gates are satisfied, the HUD names the outstanding hatch and/or oxygen blocker instead of appearing stuck.

## Controls contract

| Input | Action |
| --- | --- |
| Left click | Select a resident or fixture; repeated clicks cycle stacked residents and an occupied fixture; place the active order or blueprint |
| Left-drag | Paint Dig or Cancel orders across multiple tiles |
| Right click | Return to Select mode |
| `Esc` | Close reopened Help or the priorities board when open; otherwise return to Select mode |
| `E` | Activate Dig |
| `X` | Activate Cancel Designation |
| `P` | Open or close the crew work priorities board |
| Roster **PRIORITIES [P]** | Open the crew work priorities board |
| Work-priority cell | Cycle `1 → 2 → 3 → 4 → OFF → 1` |
| Bottom build buttons | Place the selected fixture blueprint on carved floor |
| Bottom **HELP** | Reopen the stabilization checklist and pause behind it |
| `W` `A` `S` `D` / arrow keys | Pan the camera |
| Middle-drag | Pan the camera |
| Mouse wheel | Zoom within the supported limits |
| `F` or `Home` | Center on the selected resident, selected hatch, or sealed chamber |
| `Space` | Pause or resume the simulation |
| `1` `2` `3` | Set 1×, 2×, or 3× speed and resume |

The build toolbar labels and costs are **BUNK $8**, **LUMEN $5**, **CHARGE $18**, **GROW $12**, **NUTRI $10**, **BAY $4**, **AIR $14**, and **REC $8**. Air Recycler, Rec Console, and Help have no keyboard shortcut. Selecting a completed consumer exposes its fixed power tier and lets the player enable or disable it. Any completed non-core fixture can be removed for a 50% salvage refund.

## Power contract

The emergency core supplies 2 power and a completed Charge Node supplies 7. The required powered load after one Charge Node is exactly 9:

| Consumer | Demand | Fixed priority |
| --- | ---: | --- |
| Air Recycler | 3 | CRITICAL |
| Lumen | 1 | HIGH |
| Nutrient Station | 2 | NORMAL |
| Grow Tray | 3 | LOW |
| Rec Console | 1 | OPTIONAL |

Brownouts shed the lowest fixed tier first in this exact order:

1. Rec Consoles
2. Grow Trays
3. Nutrient Stations
4. Lumens
5. Air Recyclers

Within one fixture kind, newer fixtures shed before older fixtures. The critical-route Lumen, Grow Tray, Nutrient Station, and Air Recycler consume all 9 power supplied by the core plus one Charge Node. Adding a Rec Console therefore sheds that optional 1-power load until the player disables the Lumen, removes another served consumer, or adds another Charge Node. Air Recyclers remain the most protected load but still go offline if available supply cannot meet their full 3-power demand.

## Mood and recreation contract

| Rule | Deterministic value |
| --- | --- |
| Mood range and start | 0–100; every resident starts at 72 |
| Awake baseline | -18 mood per 40-second day |
| Darkness | Additional -30 mood per day |
| Hunger | Additional -12 mood per day while food is below 35 |
| Exhaustion | Additional -12 mood per day while rest is below 30 |
| Low oxygen | Additional -24 mood per day while oxygen is at or below 35% |
| Fully stacked awake pressure | -96 mood per day |
| Protected states | Sleep and physically active Rec Console use suspend passive mood loss |
| Unbedded collapse | Waking from floor sleep costs 12 mood once |
| Low-mood work speed | Mood below 30 multiplies work by 0.70; combined need penalties have a 0.35 floor |
| HUD tiers | STEADY at 70+, STRAINED at 40–69.999, STRESSED above 9 and below 40, BREAK RISK at 9 or lower |
| Stress-break fallback | Mood at or below 9 starts a 7-second break and restores 8 mood when complete |
| Severe mood | Mood at or below 5 costs 5 health per day |
| Recreation trigger | Mood at or below 35 seeks the nearest reachable powered free console |
| Console recovery | +18 mood per simulation second while present; finishes at exactly 85 |
| Rec Console | 8 salvage, 5-second assembly, 1 power, OPTIONAL tier, one resident at a time |

Recreation remains autonomous self-care, not a work permission or victory gate. Hunger, sleep, loss of console power, deconstruction, death, and the pressure warning safely release console reservations.

## Work-priority contract

The board contains Dig, Haul, Craft, and Cook for every resident. New residents start at 3 in all four categories.

| Setting | Assignment behavior |
| --- | --- |
| `OFF` / `0` | The resident cannot claim work in this category |
| `1` | Highest enabled ordinary-work priority |
| `2` | Runs after that resident's priority-1 work |
| `3` | Normal new-game and legacy-enabled default |
| `4` | Lowest enabled ordinary-work priority |

**DIG** governs excavation. **HAUL** governs rubble recovery, blueprint supply, and emergency patch delivery. **CRAFT** governs fixture assembly and hatch patching. **COOK** governs meal preparation at a powered Nutrient Station.

Emergency hatch work outranks all numbered ordinary-work priorities but still requires its category above OFF. For ordinary work, lower numeric priority wins before the existing job-kind, distance, and job-ID ties; resident ID resolves equal worker claims. Changing an enabled number affects the next claim without interrupting current work. Switching an active category OFF releases the job immediately and safely restores any carried material.

## Day-seven outcomes

Victory is available after 280 simulation seconds and requires all three conditions:

- At least one living resident
- A sealed maintenance hatch
- Vault oxygen at or above 15%

Oxygen is critical at or below 15%, so the exact 15% boundary is both breathable for the victory gate and visibly critical in the survival HUD. If the clock completes while the hatch is open or oxygen is below 15%, play continues and the HUD identifies the unmet gate. Loss occurs when no residents remain alive.

## How to review

Use Godot 4.7.x; 4.7.2 is the repository's documented reference version.

```bash
godot --editor --path .
```

Run the project with **F5**, then exercise this route:

1. Confirm a new wing opens paused with 12 meals, 4 raw food, 48 salvage, 100% oxygen, four living residents, a 2-power emergency core, one Lumen, and one Salvage Bay.
2. Start the shift, reopen **HELP**, and confirm simulation time does not advance while the checklist is visible. Close it with **CLOSE** and **Esc** in separate checks; confirm each restores the prior running or paused state.
3. Confirm tool guidance explains that right-click/**Esc** returns to Select and **X** activates Cancel, and that the active tool's help returns after transient messages.
4. Designate a connected excavation chain. Confirm rubble yields 3 salvage per completed tile only after hauling and the checklist advances at 12 completed excavations.
5. Build two Bunks, one Charge Node, one Air Recycler, one Grow Tray, and one Nutrient Station. Confirm the checklist requires the food and air fixtures to be powered and reports missing Cook coverage.
6. Keep 4 salvage and Haul/Craft coverage ready. At 60 seconds, confirm the warning pauses at 1× and urgent delivery and patch work override numbered priorities without ignoring OFF.
7. Confirm the required powered load exactly fills 9 supply. Queue an optional Rec Console, observe it shed first, then disable the Lumen or add capacity and confirm the console becomes powered.
8. Use **P** to confirm the optional board still cycles `1 → 2 → 3 → 4 → OFF → 1`, preserves pause/tool state, and shows live work coverage.
9. Continue the real-order route through day seven. Confirm all four residents survive, the hatch is sealed, and final oxygen is at least 15%.
10. Complete a day-seven clock with a deliberately unmet hatch or oxygen gate and confirm the HUD names the blocker. Resolve it and confirm the victory message appears.
11. Start a fresh wing and issue no player orders. Confirm the unmanaged wing still reaches colony loss before day seven.

## Automated verification

Run the complete repository check from the repository root:

```bash
scripts/check.sh
```

The default form expects `/tmp/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64`. To use another executable, pass it as the first argument:

```bash
scripts/check.sh /absolute/path/to/Godot_v4.7.2-stable_linux.x86_64
```

Or set `GODOT_BIN`:

```bash
GODOT_BIN=/absolute/path/to/godot scripts/check.sh
```

The full command runs the headless editor import, core gameplay suite, mood/recreation suite, work-priorities suite, breach-modal speed-key regression, and five-frame boot check in an isolated temporary user-data directory.

The core acceptance coverage includes both sides of the balance target: a staged 12-excavation required route must preserve all four residents, seal the hatch, finish above the low-air band, retain food, and leave at least 10 salvage; a 15-designation optional-recreation route must also win with at least 7 salvage; and an untouched wing must still fail before day seven.

## Save and compatibility contract

- Save schema remains version 1.
- Existing breach, oxygen, power-disable, mood/recreation, and numeric work-priority fields retain their compatibility behavior.
- Numeric priorities remain integers from 0 through 4; legacy enabled permissions migrate to 3 and disabled permissions migrate to OFF.
- Missing priority data defaults every work category to 3.
- Loading returns the game paused and reconstructs jobs, material reservations, recreation reservations, and transient UI safely.
- The starting-kit tune changes new-wing defaults only; valid existing saves retain their saved inventory and simulation state.

## Known limitations and scope boundary

- Placeholder geometry, colors, resident markers, controls, and silent presentation remain; final art and audio are outside this slice.
- Priorities cover four broad work categories only. There are no skills, passions, schedules, shifts, zones, direct movement, forced jobs, or per-task priorities.
- Oxygen remains one vault-wide percentage. There is no spatial gas, diffusion, room pressure graph, pipe network, or wiring simulation.
- There is no broader medical system, surface play, caravans, factions, research, mods, multiplayer, IAP, ads, analytics, mobile export, or store shipping.
- Combat, enemies, raiders, weapons, repeated incidents, and procedural events remain outside the first-playable boundary.

Slice 7 ends at a clearer, more forgiving version of the same sealed-wing day-seven objective. It does not merge or ship the game and does not introduce another major system.
