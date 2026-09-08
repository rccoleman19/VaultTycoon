# Vault Tycoon

Vault Tycoon is an original underground colony-survival prototype built with Godot 4. A crew of four residents begins inside a sealed vault wing. Dig into the surrounding rock, recover salvage, furnish and light the new rooms, keep food, rest, mood, power, and shared oxygen stable, and contain the wing's first maintenance-hatch pressure breach through seven complete in-game days.

This repository contains the desktop gameplay stack through Slice 12: the first-playable sealed wing, one deterministic environmental breach, one vault-wide oxygen percentage, deterministic power brownouts with priority shedding, per-resident mood with basic powered recreation, a crew-wide work priorities board, first-session balance and help polish, Medical Beds with basic injury recovery, paintable stockpile zones for salvage, raw-food, and meal drop-offs, visible floor darkness with controllable Lumen coverage, and persistent single-resident drafting with direct moves and one-shot forced work. Lighting is a deterministic per-cell check rather than a line-of-sight or room simulation, while oxygen and power remain deliberately vault-wide resources rather than spatial gas or wiring simulations. The project does not include a surface map, caravans, factions, combat, research, mods, multiplayer, IAP, ads, analytics, store packaging, final art or audio, mobile export, a full disease/surgery tree or drugs, a multi-room sealed-door graph, or any other full atmosphere simulation.

## Requirements

- Godot **4.7.2**, standard build (the project uses GDScript, not .NET)
- Matching Godot 4.7.2 export templates when producing desktop builds
- A mouse and keyboard for the current first-playable UI

The project uses the GL Compatibility renderer and opens at a 1280×720 reference resolution.

## Run from source

From the repository root, open the project in Godot:

```bash
godot --editor --path .
```

Then press **F6** to run the open main scene or **F5** to run the project. The configured startup scene is `res://scenes/main.tscn`.

To launch the game directly without opening the editor:

```bash
godot --path .
```

If your installation exposes `godot4` or an absolute executable path instead of `godot`, substitute that command in the examples. Confirm the exact engine version with `godot --version`; use 4.7.2 to match this project.

## First shift

The game opens paused on the seal-stabilization checklist. Select **BEGIN SHIFT** to play. Use **HELP** in the lower toolbar to reopen the checklist at any time; the simulation pauses while Help is visible, and closing it restores the prior running or paused state.

Follow this forgiving first-session route:

1. Choose **DIG** or press **E**, then click or drag across at least 12 rock tiles. Every designation must connect to carved floor, directly or through adjacent dig designations. Residents with Dig above OFF excavate the reachable front of the chain.
2. Let residents haul the rubble to a Salvage Bay. Each completed rock tile yields 3 salvage only after it is hauled.
3. Place at least two **BUNK $8** blueprints on carved floor. Residents with Haul above OFF deliver their salvage and residents with Craft above OFF assemble them.
4. Build one **CHARGE $18** Charge Node. Together with the 2-power emergency core, it raises supply to 9 power.
5. Build and power **AIR $14**. The Air Recycler uses 3 power, has the grid's highest fixed consumer priority, and restores 0.8 oxygen percentage points per simulation second. The emergency core cannot power it by itself.
6. Build and power **GROW $12** and **NUTRI $10**. Keep both Haul and Cook above OFF: the Grow Tray creates raw-food cargo every 9 seconds, a cook converts 1 stored raw food into 1 meal, and a hauler must deliver each output to a reachable painted zone (or the Salvage Bay/chamber fallback) before it enters the usable inventory. Painting a **ZONE** near both food fixtures shortens these trips.
7. Keep at least 4 salvage uncommitted and keep at least one living resident's Haul and Craft above OFF. At exactly 60 simulation seconds, the maintenance-hatch warning pauses the shift, resets speed to 1×, focuses the hatch, and interrupts recreation.
8. Choose **RESUME RESPONSE**. Emergency work overrides numeric work ranks: an eligible hauler delivers the 4-salvage patch and an eligible crafter completes 8 seconds of patch work. The hatch opens at the exact 80-second boundary if the patch is unfinished, then vents 2.5 oxygen points per second until sealed.
9. Optionally build **REC $8**. A Rec Console supports mood but is not required to win. The core and one Charge Node supply 9 power, exactly consumed by the starting Lumen, Grow Tray, Nutrient Station, and Air Recycler; disable the Lumen or build another Charge Node to serve the console's additional 1-power load. A disabled or brownout-shed Lumen stops lighting nearby cells; awake residents outside any other powered Lumen's coverage suffer the additional 30 mood loss per day from darkness. Each completed, powered Lumen covers the exact inclusive Chebyshev radius of 5 cells around it: an 11×11 square with no line-of-sight or room-boundary test. Use **LIGHT MAP [L]** to inspect that coverage without changing the simulation. At 35 mood or below, a resident seeks a powered free console and recovers to 85.
10. Optionally press **P** or choose **PRIORITIES [P]** to specialize ordinary work. Every resident starts at priority 3 for Dig, Haul, Craft, and Cook. A cell cycles `1 → 2 → 3 → 4 → OFF → 1`; 1 is highest, 4 is lowest, and OFF disables automatic claims in that category for that resident.
11. Optionally select one resident and press **R** (or use the inspector) to draft them. A drafted resident suspends autonomous work and self-care; right-click one reachable carved-floor cell to replace their current move, and they remain drafted and idle on arrival. Undraft them to resume autonomy. With a selected undrafted resident, right-click a contextual queued job to force that exact job once, even when its work rank is lower or OFF. Prerequisites and reachability still apply, and an already reserved job is never stolen.
12. Keep at least one resident alive, seal the hatch, and finish seven full days with oxygen at or above 15%. If day seven completes before both final gates are satisfied, the HUD identifies whether the hatch or oxygen is still blocking victory.

The simulation starts with 12 meals, 4 raw food, 48 salvage, 100% oxygen, an emergency core, one Lumen, and one Salvage Bay. Twelve excavations add 36 recoverable salvage, bringing the critical-route pool to 84: enough for two bunks, one Charge Node, one Grow Tray, one Nutrient Station, one Air Recycler, and the 4-salvage hatch patch, with 10 salvage left for one recoverable mistake. A 15-tile expansion brings the pool to 93 and leaves 7 salvage after adding the optional Rec Console and patching the hatch. Expansion is still required, and an untouched wing still fails before day seven.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a resident or fixture; repeated clicks cycle stacked residents and an occupied fixture; place the active order/blueprint |
| Left-drag | Paint Dig, Cancel, or Zone orders across multiple tiles |
| Right click | With one resident selected, replace their drafted move or force one contextual queued job; otherwise return to Select mode |
| `Esc` | Close reopened Help or the priorities board if open; otherwise return to Select mode |
| `E` | Activate Dig |
| `X` | Activate Cancel Designation |
| `R` / resident inspector **DRAFT**/**UNDRAFT** | Toggle persistent draft for the selected living resident |
| `P` | Open or close the crew work priorities board |
| `L` or right-HUD **LIGHT MAP [L]** | Toggle the transient Lumen-coverage overlay; view-only and not saved |
| Roster **PRIORITIES [P]** | Open the crew work priorities board |
| Work-priority cell | Cycle `1 → 2 → 3 → 4 → OFF → 1`; lower numbers run first |
| Bottom build buttons | Place the selected fixture blueprint on carved floor; **AIR $14** selects the Air Recycler and **REC $8** the Rec Console |
| Bottom **HELP** | Open the stabilization checklist and pause behind it; closing restores the prior run/pause state |
| `W` `A` `S` `D` / arrow keys | Pan the camera |
| Middle-drag | Pan the camera |
| Mouse wheel | Zoom between the supported map limits |
| `F` or `Home` | Center on the selected resident or maintenance hatch, or on the sealed chamber |
| `Space` | Pause/resume simulation |
| `1` `2` `3` | Set 1×, 2×, or 3× speed and resume |

Build tools, Help, the lighting view, and the work priorities board are available in the HUD. With one living resident selected, press **R** or use the inspector's **DRAFT**/**UNDRAFT** action. A drafted resident right-clicks to one reachable carved-floor destination and remains drafted and idle after arrival; a selected undrafted resident right-clicks a matching queued job to force it once. A newly accepted command replaces that resident's previous manual command. Rejected, unreachable, prerequisite-blocked, and already-reserved targets leave current work untouched. Manual commands can be issued while paused and preserve pause, speed, selection, and the active map tool. Without a selected resident, right-click returns to Select; **Esc** also returns to Select, and **X** activates Cancel. **P** toggles the board, the roster's **PRIORITIES** action opens it, and **CLOSE** or **Esc** dismisses it. Opening or editing the board does not change the current pause state, speed, selection, or map tool. Press **L** or use right-HUD **LIGHT MAP [L]** to toggle a transient coverage overlay. The overlay is observational only: it does not pause or resume the simulation, alter speed, selection, tools, pathing, power, or mood, and it is not written to the save. Opening **HELP** pauses behind the checklist; **CLOSE** or **Esc** restores the simulation's prior running or paused state. Help has no keyboard shortcut. The active tool's instructions return after transient placement, warning, and error messages expire. The Air Recycler uses **AIR $14** and the Rec Console uses **REC $8**; neither has a keyboard shortcut. Selecting a completed consumer shows its fixed power priority and lets you disable or re-enable it; a selected Lumen additionally reports its online state and exact coverage. These generic fixture controls work while paused, and any completed non-core fixture can be removed for a 50% salvage refund. **Cancel** removes dig designations and unfinished blueprints; salvage already delivered to a canceled blueprint is refunded. The maintenance hatch also accepts direct forced supply and patch jobs when their normal prerequisites are satisfied.

## Gameplay systems

- **MapGrid:** a 50×36 grid of 24-pixel cells, initially solid rock except for a 12×10 sealed chamber. Only the outer steel boundary is permanently undiggable.
- **Residents and Needs:** four residents track food, rest, overall mood, and health. Awake mood loses 18 points per day from baseline strain, plus 30 in darkness, 12 each while hungry or exhausted, and 24 while vault oxygen is at or below 35%. Low mood slows work; critical mood triggers a costly unstructured stress break, and prolonged severe mood can damage health. Each living resident consumes 0.08 oxygen percentage points per simulation second and takes 4 health damage per second while oxygen is at or below 15%. Draft is persistent per resident: while drafted, all autonomous work, self-care, and breach response are suspended, but needs, oxygen consumption, low-oxygen damage, and other environmental effects continue normally.
- **JobSystem:** automatically assigns reachable excavation, rubble and food-output hauling, blueprint supply, construction, cooking, and urgent breach-response work according to each resident's numeric Dig, Haul, Craft, and Cook priority. OFF excludes automatic claims; among ordinary available work, priority 1 is considered before 2, then 3, then 4. Residents with the best available priority claim first, with resident ID as the deterministic worker tie-break; each resident then retains the existing job-kind, distance, and job-ID tie-breaks. A selected undrafted resident can instead receive one contextual forced job. A valid force bypasses numeric ranks and OFF for that exact job, but still requires a reachable, currently valid target and never steals another resident's reservation. Critical self-care and urgent hatch response may interrupt ordinary forced work. Hatch supply and patch work can themselves be forced directly when their prerequisites are satisfied. Drafted residents never claim automatic work or emergency response; they accept only a replaceable direct move to reachable carved floor until undrafted.
- **Construction:** bunks cost 8 salvage, lumens 5, Charge Nodes 18, Grow Trays 12, Nutrient Stations 10, Salvage Bays 4, Air Recyclers 14, and Rec Consoles 8.
- **PowerGrid:** the emergency core supplies 2 power and a completed Charge Node supplies 7. Lumens and Rec Consoles consume 1, Nutrient Stations 2, and Grow Trays and Air Recyclers 3. The HUD reports supply, enabled demand, served power, disabled demand, and any brownout shed load. Brownouts shed the lowest-priority enabled consumers first in this exact fixed order: Rec Consoles, Grow Trays, Nutrient Stations, Lumens, then Air Recyclers. Within a fixture kind, newer fixtures shed before older fixtures. When shedding reaches a Lumen, it stops lighting nearby cells; awake residents left outside all other powered Lumen coverage suffer the additional 30 mood loss per day from darkness. Air Recyclers are always protected at the highest priority, but still go offline when available supply cannot satisfy their 3-power demand; that removes recycler output and can cascade into oxygen danger. Players can recover by disabling optional consumers, removing non-core fixtures for partial salvage, or adding Charge Node capacity.
- **Lighting and darkness:** each completed, powered Lumen costs 5 salvage, takes 5 seconds to assemble, consumes 1 power at the fixed HIGH priority, and lights cells whose horizontal and vertical offsets are each at most 5. That inclusive Chebyshev-radius-5 rule forms an 11×11 square and does not test line of sight, rock occlusion, doors, or rooms. Overlapping coverage remains simply lit. Unlit carved floor receives a visible darkness layer; power changes, manual disable/enable, completion, removal, New Wing, and load all update the derived view. The right HUD reports lit-floor coverage, online Lumens, and how many living residents are dark. Resident and Lumen inspectors expose the same state, and an alert reports dark residents. **LIGHT MAP [L]** temporarily makes coverage explicit but does not change any simulation rule.
- **Mood and recreation:** recreation is autonomous self-care rather than a work permission. At 35 mood or below, a resident deterministically chooses the nearest reachable, powered, unoccupied Rec Console, with building ID as the tie-breaker. Mood recovers only after the resident reaches it, at 18 points per simulation second, until exactly 85. One console has one seat. Hunger, sleep, loss of power, deconstruction, death, and the pressure warning all release the reservation safely. Passive mood drain pauses during sleep and active console use.
- **FoodSystem:** starts with 12 stored meals, 4 stored raw food, and 48 salvage. A powered Grow Tray produces 1 pending raw food every 9 simulation seconds. Four seconds of cooking at a powered Nutrient Station consumes 1 stored raw food and produces 1 pending meal. Food becomes usable only after Haul work delivers it to a reachable zone or fallback; healthy meal reserves allow output to batch so hauling does not monopolize the crew.
- **OxygenSystem:** tracks one shared percentage for the entire vault, starting at 100% and clamped from 0% to 100%. Living residents consume 0.08 points per second each, every powered Air Recycler restores 0.8 points per second, and an open hatch vents 2.5 points per second. The low threshold is 35%; at or below the 15% critical threshold, all living residents take 4 health damage per second.
- **DayCycle:** one game day lasts 40 simulation seconds. Pausing stops the clock; speed controls multiply it. Victory becomes available after 280 simulation seconds, when seven full days have elapsed, and requires at least one living resident, a sealed hatch, and breathable oxygen at or above 15%.
- **Breach pressure:** one deterministic maintenance-hatch warning begins at exactly 60 simulation seconds. Its first appearance pauses the simulation, resets speed to 1×, and focuses the hatch. The hatch opens at exactly 80 seconds if the 4-salvage, 8-second patch is unfinished; while open, it adds a 2.5-point-per-second oxygen loss until sealed.
- **PlayerOrders:** builds the 1280×720 HUD, reopenable Help/checklist, roster and adjacent **PRIORITIES [P]** control, resident **DRAFT**/**UNDRAFT** control and contextual right-click feedback, transient **LIGHT MAP [L]** coverage view, contextual inspector, alerts, lower map/build/save toolbar including **AIR $14**, **REC $8**, **MED $8**, **ZONE**, and **HELP**, the complete crew-by-work priority board, stored-versus-pending food counts, power supply/demand/brownout readouts, lit-floor/online-Lumen/dark-crew telemetry, every living resident's mood, active mood and lighting factors, fixed-priority fixture labels and paused recovery controls, vault-atmosphere meter and rate breakdown, breach pressure/blocker readout and focus control, day-seven victory blockers, and outcome screens in GDScript. The checklist distinguishes the required powered and staffed food/air chain from optional recreation, work specialization, and manual control.
- **SaveLoad:** uses a crash-recoverable temporary-file replacement for one versioned local JSON snapshot and restores the map, residents, per-category work priorities, persistent draft/manual-command state, fixtures (including manually disabled power loads), stored inventory, pending food cargo, jobs, time, camera, breach state, oxygen, mood/recreation state, and outcome state. An interrupted replacement preserves a recoverable previous file. The schema remains version 1: manual-control state, numeric priorities, and pending food-haul arrays are optional compatible extensions; older boolean work permissions migrate to priority 3 or OFF, earlier `light_mood` snapshots migrate to canonical mood, and missing manual-control, recreation, or food-haul state defaults safely. Lighting remains derived from fixture and power state, so saves add no lighting payload; the transient Light Map view is not serialized or restored.

The main scene keeps these systems as separate child nodes under `VaultGame`, with `VaultGame` coordinating a fixed 0.1-second simulation tick.

## Work priorities

The priority board shows every resident as a row and **DIG**, **HAUL**, **CRAFT**, and **COOK** as columns. New residents start at priority 3 in every category. Clicking one cell changes only that resident and category, using this fixed cycle. The board also reports how many living residents remain eligible in each category and calls out any category with no eligible crew.

| Setting | Assignment behavior |
| --- | --- |
| `OFF` | The resident cannot claim jobs in this category |
| `1` | Highest ordinary-work priority |
| `2` | Runs after that resident's priority-1 work |
| `3` | Normal starting and legacy-enabled priority |
| `4` | Lowest enabled ordinary-work priority |

**DIG** covers excavation. **HAUL** covers rubble recovery, raw-food and meal output, blueprint supply, and emergency patch delivery. **CRAFT** covers fixture assembly and emergency hatch patching. **COOK** covers meal preparation at a powered Nutrient Station.

Turning a category OFF immediately releases that resident from an automatically claimed job in the disabled category, including safely returning carried salvage or food to its source job. Changing one enabled numeric value to another does not interrupt the current job; it affects the resident's next automatic claim. Emergency hatch supply and patch work remain an absolute override above the numeric board order for undrafted residents, while OFF Haul or Craft remains ineligible for automatic response and produces the existing blocker warning. A valid one-shot forced order is the deliberate exception: it bypasses both the numeric rank and OFF for that exact job only.

## Manual draft and forced orders

Manual control applies to one selected living resident at a time. Draft state belongs to the resident rather than the selection, so selecting something else, reaching a move destination, pausing, and changing speed or map tools do not undraft them.

| Command rule | Slice 12 behavior |
| --- | --- |
| Toggle | `R` or the selected-resident **DRAFT**/**UNDRAFT** inspector action |
| Drafted autonomy | No automatic work, eating, sleeping, medical care, recreation, stress-break behavior, or breach response |
| Drafted right-click | Replace the resident's single direct move with a reachable carved-floor destination |
| Arrival | Remain drafted and idle until another move is issued or the resident is undrafted |
| Undrafted right-click | Force the exact contextual queued job once |
| Forced eligibility | Bypass numeric work rank and OFF; still require the job's live prerequisites and a reachable target |
| Reservations | Never steal a job already reserved by another resident |
| Forced hatch work | Direct forced patch-supply and patch-work orders are supported when their phase prerequisites are met |
| Interruption | Critical self-care and urgent hatch response can interrupt ordinary forced work |
| Replacement | One accepted manual command replaces the prior command; there is no command queue |
| Rejection | Invalid, unreachable, unavailable, or reserved targets do not disturb current work or its reservation |
| Paused input | Commands may be issued while paused without changing pause, speed, selection, or the active map tool |
| Ongoing simulation | Draft suspends autonomy, not needs or hazards; oxygen use, mood/need changes, and environmental damage continue |
| Persistence | Optional schema-1 fields preserve per-resident draft and manual-command state; legacy omission means undrafted with no command |

Starting a New Wing clears every draft and manual command. Loading returns paused with valid manual state restored safely. The feature remains deliberately single-selection and single-command: there is no multi-select, shift queue, patrol route, combat stance, or player-authored work queue.

## Mood and recreation balance

| Rule | Deterministic weight |
| --- | --- |
| Mood meter | Clamped to 0–100; every resident starts at 72 |
| Awake baseline | -18 mood per 40-second day |
| Darkness | Additional -30 mood per day while awake and outside all powered Lumen coverage |
| Hunger | Additional -12 mood per day while food is below 35 |
| Exhaustion | Additional -12 mood per day while rest is below 30 |
| Low oxygen | Additional -24 mood per day while vault oxygen is at or below 35% |
| Fully stacked awake pressure | -96 mood per day: baseline, dark, hungry, exhausted, and low O2 |
| Protected recovery states | Sleeping and physically active Rec Console use suspend passive mood loss |
| Unbedded collapse | Waking from floor sleep costs 12 mood once |
| Work speed | Mood below 30 multiplies work by 0.70; combined need penalties retain a 0.35 floor |
| HUD tiers | STEADY at 70+, STRAINED at 40–69.999, STRESSED above 9 and below 40, BREAK RISK at 9 or lower |
| Stress-break fallback | Mood at or below 9 starts a 7-second break that restores 8 mood |
| Severe mood | Mood at or below 5 costs 5 health per day |
| Recreation trigger | Mood at or below 35 seeks the nearest reachable powered free console |
| Console recovery | +18 mood per simulation second while physically present; finishes at exactly 85 |
| Rec Console fixture | 8 salvage, 5-second assembly, 1 power, OPTIONAL priority, one resident |

Darkness has no direct movement, pathing, work-speed, health, power, or oxygen modifier. Its simulation effect is the existing mood pressure above, which can still lead indirectly to the documented low-mood work penalty or severe-mood health loss. The visible darkness layer and **LIGHT MAP [L]** only communicate the same deterministic coverage used by mood.

Slice 7 does not apply a recent-damage mood modifier because the current resident model has no damage-recency timer or saved history.

## Local save

Use **SAVE** and **LOAD** in the lower toolbar. The game also checkpoints at the start of each new day and saves the victory state. Loading returns the game in a paused state.

The one-slot save is `user://vault_wing_save.json`. With Godot's default per-project user-data directory, that resolves to:

- Linux: `~/.local/share/godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- macOS: `~/Library/Application Support/Godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- Windows: `%APPDATA%\Godot\app_userdata\Vault Tycoon\vault_wing_save.json`

Deleting or replacing this file resets or overwrites the only local slot. Save schema version 1 rejects malformed or incompatible files rather than partially loading them. Breach, oxygen, per-fixture manual-disable state, canonical mood, active recreation state, numeric work priorities, pending food-output jobs, and optional per-resident draft/manual-command state remain compatible extensions. New saves retain the legacy boolean permission map alongside the numeric map. A legacy enabled permission becomes priority 3, a disabled permission becomes OFF, and a missing work-priority map defaults every category to 3. Legacy `light_mood` values migrate to mood; missing manual-control state defaults to undrafted with no command, missing recreation and pending-food fields default to idle/empty, and stale reservations are reconciled rather than left dangling. Lighting coverage, floor darkness, online counts, and dark-crew counts are reconstructed from loaded fixture and power state. The transient Light Map view is UI state and is never saved.

## Full headless verification

Run the complete repository check from the repository root:

```bash
scripts/check.sh
```

That default form expects the development binary at `/tmp/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64`. On another installation, pass the Godot executable as the first argument:

```bash
scripts/check.sh /absolute/path/to/Godot_v4.7.2-stable_linux.x86_64
```

Or set `GODOT_BIN`:

```bash
GODOT_BIN=/absolute/path/to/godot scripts/check.sh
```

The script uses an isolated temporary user-data directory and runs every checked suite: headless editor import, core gameplay, mood/recreation, work priorities, breach-modal speed keys, medical care, stockpile zones, food hauling, lighting/darkness control (`tests/test_lighting_darkness.gd`), manual draft/forced orders, and a five-frame main-scene boot. A successful run ends with `All Vault Tycoon headless checks passed.`

## Desktop exports

Install the **Godot 4.7.2** export templates first: open **Editor → Manage Export Templates**, choose **Download and Install**, and verify the installed template version matches the editor. The checked-in `export_presets.cfg` defines unsigned development presets for Linux, macOS, and Windows.

In the editor, use **Project → Export**, select one of the presets below, choose **Export Project**, and retain the configured output path:

- **Linux:** `exports/linux/VaultTycoon.x86_64`
- **macOS:** `exports/macos/VaultTycoon.zip`
- **Windows Desktop:** `exports/windows/VaultTycoon.exe`

The equivalent reproducible command-line workflow from the repository root is:

```bash
mkdir -p exports/linux exports/macos exports/windows
godot --headless --path . --export-release "Linux" "exports/linux/VaultTycoon.x86_64"
godot --headless --path . --export-release "macOS" "exports/macos/VaultTycoon.zip"
godot --headless --path . --export-release "Windows Desktop" "exports/windows/VaultTycoon.exe"
```

Run the Linux build with:

```bash
chmod +x exports/linux/VaultTycoon.x86_64
./exports/linux/VaultTycoon.x86_64
```

Extract the macOS ZIP on a Mac and open the contained `.app`. Run `VaultTycoon.exe` on Windows. These are unsigned development builds: operating-system security prompts are expected, and no signing or notarization is configured. If an export produces a companion `.pck`, keep it beside the executable. The entire `exports/` directory is ignored by Git.

Cross-exporting creates the target files when the matching templates are installed, but final smoke testing should happen on each target operating system. macOS signing/notarization and Windows code signing are deliberately outside this slice.

## Scope boundary

Slice 7 polished the sealed-wing day-seven survival objective; Slice 8 adds buildable Medical Beds and Rest-Medical recovery; Slice 9 adds floor-painted stockpile zones for salvage; Slice 10 sends Grow Tray and Nutrient Station output through those destinations; Slice 11 makes the existing powered-Lumen rule visible and controllable through floor darkness, live HUD telemetry, and a transient coverage map; Slice 12 adds persistent per-resident drafting, one replaceable direct move, and one-shot contextual forced work for a selected resident. The current stack includes one deterministic maintenance-hatch pressure event, one aggregate oxygen percentage, one deterministic vault-wide power allocator with brownout shedding, derived per-cell Lumen coverage, one-seat basic recreation, one numeric priority for each resident/work-category pair, basic one-patient medical care, generic stockpile destination cells, and limited direct resident control. It does not add light intensity, color, falloff, line of sight, rock or wall occlusion, ray casting, a room graph, day/night lighting, per-cell inventories, stockpile capacity or filters, conveyors, raw-input delivery, meal-fetch trips, resident skills, aptitudes or passions, schedules or shifts, multi-resident selection, player-authored multi-order queues, persistent individual-task priorities, work-assignment zones, patrols, combat stances, relationships, social recreation, memories, room beauty, comfort, recreation variety, a full disease/surgery tree, drugs, wiring, circuits, batteries, fuel, spatial gas cells, multiple gases, diffusion, pressure zones, oxygen pipe networks, multiple independently sealed rooms, a sealed-door/room graph, or any other full atmosphere model. It also does not add surface expeditions, caravans, factions, research, mods, multiplayer, IAP, ads, analytics, final art or audio, mobile export, store packaging, raiders, enemies, weapons, combat, or repeated/procedural incidents.


## Slice 8 — Medical beds

Build **MED $8** for 8 salvage and 8 seconds of assembly. No power is required.
Injured residents at 95 HP or below automatically claim one reachable, completed Medical Bed and
perform **Rest-Medical**, recovering 2 HP per simulation second at the bed, capped
at 100 HP. A bed serves one patient; travel provides no healing. Rations interrupt
care; hungry residents seek food before starting care. Low meal stocks prioritize available cooking jobs, and the active hatch response takes precedence. Existing hunger, O2, breach,
and mood damage remain in effect. Medical rest restores rest while treatment runs.

Select a Medical Bed and **DISABLE** to deny care, or **ENABLE** to restore it.
The HUD shows injured crew and free medical beds; resident rows retain individual
HP and activity, and the fixture inspector shows availability and its patient.
Free beds may still be unreachable from a particular resident. Deconstruction and
death release reservations. Health, fixtures, and disabled care survive save/load;
transient medical reservations are reclaimed on the next simulation tick.

Medical care is optional for victory. The managed medical regression starts with
an established food, mood, and oxygen loop, constructs a medical bed with normal
salvage delivery and build jobs, and recovers a 35 HP injury after the hatch event.
The original first-session construction routes and unmanaged failure tests remain.
`./scripts/check.sh` includes medical recovery, missing/unfinished/disabled beds,
capacity, travel, save/load, removal, death, HUD, and a managed day-seven medical
route, along with all prior suites. Godot remains 4.7.2. This slice is stacked on
PR #7 (`b6d95a5`) and targets main; merge the earlier slices first.


## Slice 9 — Stockpile zones

Use **ZONE** and click or hold the left mouse button while moving across empty
carved floor to paint a set of stockpile cells. Cyan outlines show painted cells;
**ZONE N** in the toolbar reports the total cell count (including disconnected
floor). The tooltip explains fallback behavior. Painting costs no salvage or time.
**CANCEL [X]** clears individual zone cells with the same click/drag gesture;
**Esc** or right-click returns to Select without deleting zones. Dig/build tools
remain separate. Rock, out-of-bounds cells, fixtures, blueprints, and the hatch
cannot be painted. Placing a fixture on a zone automatically clears that cell.

| Haul rule | Behavior |
| --- | --- |
| Cargo affected | Existing rubble-to-salvage hauling only |
| Preferred drop-off | Closest reachable valid zone cell by floor-path length |
| Equal-distance ties | Deterministic breadth-first traversal: left, right, up, down |
| Zones cleared or changed while hauling | Destination is recalculated on each haul update |
| No reachable zone | Existing first completed Salvage Bay; chamber center if no Bay exists |
| Inventory | Salvage is credited once on arrival to shared inventory; no cell capacity or item piles |
| Supply pickups | Building and hatch supply pickups retain the existing Bay/center behavior |
| Raw food and meals | In Slice 9, remained shared inventory without physical food-haul jobs |

Zones persist as optional `map.stockpile_cells` in schema-1 saves. Legacy saves
start without zones; malformed, duplicate, occupied, hatch, and non-floor entries
are rejected before the live game changes. New Wing clears zones.

`./scripts/check.sh` includes `tests/test_stockpile_zones.gd` alongside core,
mood/recreation, work priorities, breach-modal speed keys, medical, editor import,
and main-scene boot. The zone suite covers painting/cancel/build/HUD, physical
deposit and exact inventory credit, fallback, deterministic selection, rerouting,
save/load, legacy compatibility, invalid-load atomicity, and New Wing reset.

Slice 9 branches from Slice 8 / PR #8 at `451a442`, targets `main`, and retains the
unmerged stack. No merge or store shipping is part of this work. Conveyors, per-item
filters, physical food-haul jobs, surface systems, and the other exclusions above
were outside Slice 9's scope.


## Slice 10 — Food and meal hauling

Grow Trays and Nutrient Stations now produce physical inbound cargo. Completing a
powered Grow Tray cycle creates pending raw food at that tray. Completing four
seconds of Cook work consumes one already-stored raw food and creates a pending
meal at the station. Neither output changes the usable **RAW** or **MEALS** count
until a resident with Haul above OFF picks it up and reaches a destination.

Raw food, meals, and rubble share the same generic destination rules:

| Haul rule | Slice 10 behavior |
| --- | --- |
| Preferred drop-off | Closest reachable painted zone by floor-path length |
| Equal-distance ties | Breadth-first left, right, up, then down |
| Zone changes in flight | Recalculate and reroute without losing cargo |
| No reachable zone | First completed Salvage Bay; chamber center if no Bay exists |
| Repeated output | Accumulate at the producer; later output never joins an in-flight stack |
| Interrupted carrier | Return cargo to the pending source job for a safe retry |
| Stored inventory | Starting stock and deposited goods remain shared counters |

The resource HUD renders pending output in parentheses, and Grow Tray/Nutrient
Station inspectors show how much output from that cell is awaiting Haul. Resident
task text and the carried-item marker distinguish salvage, raw food, and meals.
When stored meal reserves are healthy, prepared output may batch before collection;
once reserves fall, meal hauling moves ahead of ordinary cooking. If the hatch
response lacks salvage, reachable rubble recovery and connected excavation move
ahead of routine food work so the emergency supply chain cannot be starved.

Schema version 1 remains unchanged. Optional `jobs.raw_food` and `jobs.meals`
arrays preserve all undeposited output, including cargo that was in flight; loading
restarts that cargo safely at its source. Legacy saves with neither field load with
no pending food. Malformed, duplicate, out-of-bounds, non-floor, or non-positive
entries reject the snapshot atomically. Starting a New Wing clears pending cargo.

`./scripts/check.sh` includes `tests/test_food_hauling.gd`. The focused suite covers
exact production boundaries, stored-versus-pending inventory, Haul OFF, repeated
and mid-flight output, preferred zones, both fallbacks, live rerouting, interruption,
producer removal, death recovery, exact-once credit, saves, legacy compatibility,
malformed-load atomicity, reset, and HUD guidance. Existing managed and unmanaged
day-seven routes remain covered.

Slice 10 branches from Slice 9 at `cc56863` on `feat/food-stockpile-haul`. It is an
unmerged desktop gameplay slice: no merge or store shipping is authorized. It does
not add conveyors, per-cell stacks, stockpile filters/capacity, heavy stack UI,
raw-food pickup into kitchens, meal-fetch trips, surface play, caravans, factions,
research, mods, multiplayer, IAP, ads, analytics, final art/audio, or mobile work.


## Slice 11 — Lighting and darkness control

Slice 11 makes the existing powered-Lumen mood rule visible and controllable
without adding a room, line-of-sight, or atmosphere simulation. Each completed,
enabled, currently powered **LUMEN $5** lights every carved floor cell whose
horizontal and vertical offsets from the Lumen are each at most 5. This inclusive
Chebyshev-radius-5 rule produces an 11x11 square centered on the fixture. Rock,
walls, doors, future rooms, and hatch geometry do not block it, and overlapping
Lumens only produce one lit state rather than intensity or stacked mood benefits.

Unlit carved floor receives a persistent darkness layer. Coverage is derived from
live fixture and power state, so it updates when a Lumen is built, enabled,
disabled, shed by brownout, restored, removed, loaded from save, or reset by New
Wing. Brownout priority still follows the fixed power ladder: Rec Consoles shed
first, then Grow Trays, Nutrient Stations, Lumens, and finally Air Recyclers. When
the allocator sheds a Lumen, that fixture immediately stops lighting its footprint,
which can increase dark floor and expose awake residents to the documented
additional 30 mood loss per 40-second day. Darkness does not otherwise change
movement, pathing, work speed, health, power, oxygen, construction, cooking, or
production.

The right HUD reports lit floor, total carved floor, the coverage percentage,
online/completed Lumens, and the number of living residents outside all powered
coverage. Resident inspection names whether the selected resident is lit or dark
and shows the resulting mood pressure. Lumen inspection reports active/offline
state, the exact 5-tile radius, the fixture footprint in carved floor cells, and
the darkness mood penalty outside coverage. The alert strip calls out dark
residents so the player can add power, disable lower-value loads, build more
Lumens, or move work closer to lit space.

Press **L** or use right-HUD **LIGHT MAP [L]** to toggle a transient coverage view.
The Light Map is informational only: it does not pause, resume, change speed,
select tools, alter pathing, allocate power, affect mood, or write save data.
Opening Help, the work-priority board, an unacknowledged hatch warning, or an
outcome blocks the shortcut the same way other view controls are blocked; repeated
key events do not flicker the overlay.

Schema version 1 remains unchanged. Lighting saves no separate payload: floor
darkness, lit-cell sets, online Lumen counts, dark-resident counts, and the visible
overlay are reconstructed from saved map cells, fixture positions, completion and
manual-disable state, and the recomputed power allocation. Legacy saves that lack
manual-disable data load with Lumens enabled by default, and Light Map visibility
always resets off after New Wing or load.

`./scripts/check.sh` includes `tests/test_lighting_darkness.gd`. The focused suite
covers exact center, axial, diagonal, and just-outside Chebyshev boundaries;
overlap; unfinished, disabled, shed, recovered, and removed Lumens; paused
enable/disable redraws; HUD, inspector, alert, and Light Map behavior; save/load
derivation; legacy compatibility; and confirmation that transient Light Map state
is never serialized. Existing core, mood/recreation, work-priority, breach,
medical, stockpile-zone, food-hauling, editor import, and boot checks remain in
the complete verification run.

Slice 11 branches from Slice 10 at `6ea2a85` on `feat/lighting-darkness`. It is an
unmerged desktop gameplay slice: no merge or store shipping is authorized. It does
not add colored light, falloff, brightness stacking, fog of war, vision, ray
casting, rock occlusion, room graphs, day/night lighting, batteries, wiring,
circuits, spatial gas cells, doors, surface play, caravans, factions, research,
mods, multiplayer, IAP, ads, analytics, final art/audio, or mobile work.
