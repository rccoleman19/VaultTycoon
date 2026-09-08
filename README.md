# Vault Tycoon

Vault Tycoon is an original underground colony-survival prototype built with Godot 4. A crew of four residents begins inside a sealed vault wing. Dig into the surrounding rock, recover salvage, furnish the new rooms, keep food, rest, mood, power, and shared oxygen stable, and contain the wing's first maintenance-hatch pressure breach through seven complete in-game days.

This repository contains the first six desktop gameplay slices: the first-playable sealed wing, one deterministic environmental breach, one vault-wide oxygen percentage, deterministic power brownouts with priority shedding, per-resident mood with basic powered recreation, and a crew-wide work priorities board. Oxygen and power are deliberately vault-wide resources rather than spatial gas or wiring simulations. The project does not include a surface map, caravans, factions, combat, research, mods, multiplayer, IAP, ads, analytics, store packaging, final art or audio, mobile export, a multi-room sealed-door graph, or any other full atmosphere simulation.

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

The game opens paused on the seal-stabilization briefing. Select **BEGIN SHIFT**, then:

1. Choose **PRIORITIES** or press **P** to open the work board. Every resident starts at priority 3 for Dig, Haul, Craft, and Cook. Click a cell to cycle `1 → 2 → 3 → 4 → OFF → 1`; 1 is highest, 4 is lowest, and OFF disables that category for that resident.
2. Choose **DIG** or press **E**, then click or drag across rock connected to carved floor by adjacent dig designations. Residents whose Dig priority is not OFF excavate the reachable front of that chain.
3. Excavated rubble becomes salvage after a resident hauls it to the Salvage Bay.
4. Place blueprints only on carved floor. Residents whose Haul and Craft priorities are not OFF supply and assemble them.
5. Build a Charge Node, then choose **AIR $14** and assemble an Air Recycler on carved floor. It uses 3 power, receives the grid's highest fixed consumer priority, and restores 0.8 oxygen percentage points per simulation second while powered. The 2-power emergency core cannot run the recycler without added capacity.
6. Build bunks for rest and add a powered Grow Tray and Nutrient Station for food. Keep Cook above OFF for at least one resident; the tray produces raw food and the station converts raw food into meals.
7. Add a Rec Console, then add another Charge Node or free at least 1 power by disabling or removing another consumer. Awake residents lose mood from daily strain, darkness, hunger, exhaustion, and low vault oxygen. At 35 mood or below they automatically reserve a powered free console, walk to it, and recover to 85. A console serves one resident at a time and its optional 1-power load is shed before production or life support.
8. Watch **VAULT ATMOSPHERE** in the right HUD. Oxygen starts at 100%, and each living resident consumes 0.08 percentage points per simulation second. The HUD shows the current percentage, net rate, resident use, recycler output, and active hatch leak; at or below 35%, awake residents also lose an additional 24 mood per day. Oxygen becomes critical at or below 15%.
9. Keep at least 4 salvage available and leave Haul and Craft above OFF for breach response. At exactly 60 simulation seconds, a maintenance-hatch pressure warning pauses the game, resets speed to 1×, focuses the breach, and interrupts recreation.
10. Resume from the warning and watch the urgent response: a resident allowed to Haul delivers 4 salvage, then a resident allowed to Craft performs the 8-second patch. Emergency work preempts every numeric board priority. The right HUD reports the grace period through the exact 80-second opening boundary, patch progress, and any missing salvage, permission, or path blocker.
11. If the hatch reaches 80 seconds unsealed, it opens and vents another 2.5 oxygen points per simulation second until patched. At or below 15% oxygen, every living resident takes 4 health damage per simulation second. To win after seven full days, keep at least one resident alive, seal the hatch, and finish with at least 15% oxygen.

The simulation starts with 8 meals, 2 raw food, 30 salvage, an emergency core, one lumen, and one Salvage Bay. Digging is part of the economy: each completed rock tile creates 3 salvage that must be hauled. The sustainable power, oxygen, and food chain costs more than the starting stock, so expansion is required.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a resident or fixture; repeated clicks cycle stacked residents and an occupied fixture; place the active order/blueprint |
| Left-drag | Paint Dig or Cancel orders across multiple tiles |
| Right click | Return to Select mode |
| `Esc` | Close the priorities board if open; otherwise return to Select mode |
| `E` | Activate Dig |
| `X` | Activate Cancel Designation |
| `P` | Open or close the crew work priorities board |
| Roster **PRIORITIES [P]** | Open the crew work priorities board |
| Work-priority cell | Cycle `1 → 2 → 3 → 4 → OFF → 1`; lower numbers run first |
| Bottom build buttons | Place the selected fixture blueprint on carved floor; **AIR $14** selects the Air Recycler and **REC $8** the Rec Console |
| `W` `A` `S` `D` / arrow keys | Pan the camera |
| Middle-drag | Pan the camera |
| Mouse wheel | Zoom between the supported map limits |
| `F` or `Home` | Center on the selected resident, or on the sealed chamber |
| `Space` | Pause/resume simulation |
| `1` `2` `3` | Set 1×, 2×, or 3× speed and resume |

Build tools and the work priorities board are available in the HUD. **P** toggles the board, the roster's **PRIORITIES** action opens it, and **CLOSE** or **Esc** dismisses it. When the board is closed, **Esc** returns to Select mode. Opening or editing the board does not change the current pause state, speed, selection, or map tool. The Air Recycler uses **AIR $14** and the Rec Console uses **REC $8**; neither has a keyboard shortcut. Selecting a completed consumer shows its fixed power priority and lets you disable or re-enable it; any completed non-core fixture can be removed for a 50% salvage refund. **Cancel** removes dig designations and unfinished blueprints; salvage already delivered to a canceled blueprint is refunded. The maintenance-hatch response creates its own urgent jobs and does not add a toolbar tool: use the right-HUD breach focus control and keep Haul and Craft above OFF.

## Gameplay systems

- **MapGrid:** a 50×36 grid of 24-pixel cells, initially solid rock except for a 12×10 sealed chamber. Only the outer steel boundary is permanently undiggable.
- **Residents and Needs:** four residents track food, rest, overall mood, and health. Awake mood loses 18 points per day from baseline strain, plus 30 in darkness, 12 each while hungry or exhausted, and 24 while vault oxygen is at or below 35%. Low mood slows work; critical mood triggers a costly unstructured stress break, and prolonged severe mood can damage health. Each living resident consumes 0.08 oxygen percentage points per simulation second and takes 4 health damage per second while oxygen is at or below 15%.
- **JobSystem:** automatically assigns reachable excavation, rubble hauling, blueprint supply, construction, cooking, and urgent breach-response work according to each resident's numeric Dig, Haul, Craft, and Cook priority. OFF excludes a work category; among ordinary available work, priority 1 is considered before 2, then 3, then 4. Residents with the best available priority claim first, with resident ID as the deterministic worker tie-break; each resident then retains the existing job-kind, distance, and job-ID tie-breaks. A hatch patch first needs a 4-salvage Haul job and then an 8-second Craft job. Emergency hatch work always outranks ordinary work regardless of its numeric Haul or Craft priority, but OFF still blocks that category. Eating, sleeping, and recreation interrupt ordinary work when needed; urgent breach response preempts recreation.
- **Construction:** bunks cost 8 salvage, lumens 5, Charge Nodes 18, Grow Trays 12, Nutrient Stations 10, Salvage Bays 4, Air Recyclers 14, and Rec Consoles 8.
- **PowerGrid:** the emergency core supplies 2 power and a completed Charge Node supplies 7. Lumens and Rec Consoles consume 1, Nutrient Stations 2, and Grow Trays and Air Recyclers 3. The HUD reports supply, enabled demand, served power, disabled demand, and any brownout shed load. Brownouts shed the lowest-priority enabled consumers first in this exact fixed order: Rec Consoles, Grow Trays, Nutrient Stations, Lumens, then Air Recyclers. Within a fixture kind, newer fixtures shed before older fixtures. Air Recyclers are always protected at the highest priority, but still go offline when available supply cannot satisfy their 3-power demand; that removes recycler output and can cascade into oxygen danger. Players can recover by disabling optional consumers, removing non-core fixtures for partial salvage, or adding Charge Node capacity.
- **Mood and recreation:** recreation is autonomous self-care rather than a work permission. At 35 mood or below, a resident deterministically chooses the nearest reachable, powered, unoccupied Rec Console, with building ID as the tie-breaker. Mood recovers only after the resident reaches it, at 18 points per simulation second, until exactly 85. One console has one seat. Hunger, sleep, loss of power, deconstruction, death, and the pressure warning all release the reservation safely. Passive mood drain pauses during sleep and active console use.
- **FoodSystem:** a powered Grow Tray yields 1 raw food every 9 simulation seconds. Four seconds of cooking converts 1 raw food into 1 meal, closely matching a four-resident wing's baseline demand.
- **OxygenSystem:** tracks one shared percentage for the entire vault, starting at 100% and clamped from 0% to 100%. Living residents consume 0.08 points per second each, every powered Air Recycler restores 0.8 points per second, and an open hatch vents 2.5 points per second. The low threshold is 35%; at or below the 15% critical threshold, all living residents take 4 health damage per second.
- **DayCycle:** one game day lasts 40 simulation seconds. Pausing stops the clock; speed controls multiply it. Victory becomes available after 280 simulation seconds, when seven full days have elapsed, and requires at least one living resident, a sealed hatch, and breathable oxygen at or above 15%.
- **Breach pressure:** one deterministic maintenance-hatch warning begins at exactly 60 simulation seconds. Its first appearance pauses the simulation, resets speed to 1×, and focuses the hatch. The hatch opens at exactly 80 seconds if the 4-salvage, 8-second patch is unfinished; while open, it adds a 2.5-point-per-second oxygen loss until sealed.
- **PlayerOrders:** builds the 1280×720 HUD, briefing/checklist, roster and adjacent **PRIORITIES [P]** control, contextual inspector, alerts, lower map/build/save toolbar including **AIR $14** and **REC $8**, the complete crew-by-work priority board, power supply/demand/brownout readouts, every living resident's mood, active mood factors, fixed-priority fixture labels and recovery controls, vault-atmosphere meter and rate breakdown, breach pressure/blocker readout and focus control, and outcome screens in GDScript. The checklist explicitly tracks powered Air Recycler and Rec Console fixtures.
- **SaveLoad:** uses a crash-recoverable temporary-file replacement for one versioned local JSON snapshot and restores the map, residents, per-category work priorities, fixtures (including manually disabled power loads), inventory, jobs, time, camera, breach state, oxygen, mood/recreation state, and outcome state. An interrupted replacement preserves a recoverable previous file. Slice 6 remains on schema version 1: numeric priorities are an optional compatible extension, older boolean work permissions migrate to priority 3 or OFF, earlier `light_mood` snapshots migrate to canonical mood, and missing recreation state defaults safely.

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

**DIG** covers excavation. **HAUL** covers rubble recovery, blueprint supply, and emergency patch delivery. **CRAFT** covers fixture assembly and emergency hatch patching. **COOK** covers meal preparation at a powered Nutrient Station.

Turning a category OFF immediately releases that resident from a job in the disabled category, including safely returning reserved carried salvage. Changing one enabled numeric value to another does not interrupt the current job; it affects the resident's next claim. Emergency hatch supply and patch work remain an absolute override above the numeric board order, while an OFF Haul or Craft category remains ineligible and produces the existing blocker warning.

## Mood and recreation balance

| Rule | Deterministic weight |
| --- | --- |
| Mood meter | Clamped to 0–100; every resident starts at 72 |
| Awake baseline | -18 mood per 40-second day |
| Darkness | Additional -30 mood per day |
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

Slice 6 does not apply a recent-damage mood modifier because the current resident model has no damage-recency timer or saved history.

## Local save

Use **SAVE** and **LOAD** in the lower toolbar. The game also checkpoints at the start of each new day and saves the victory state. Loading returns the game in a paused state.

The one-slot save is `user://vault_wing_save.json`. With Godot's default per-project user-data directory, that resolves to:

- Linux: `~/.local/share/godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- macOS: `~/Library/Application Support/Godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- Windows: `%APPDATA%\Godot\app_userdata\Vault Tycoon\vault_wing_save.json`

Deleting or replacing this file resets or overwrites the only local slot. Save schema version 1 rejects malformed or incompatible files rather than partially loading them. Slice 6 keeps schema version 1: breach, oxygen, per-fixture manual-disable state, canonical mood, active recreation state, and numeric work priorities are compatible extensions. New saves retain the legacy boolean permission map alongside the numeric map. A legacy enabled permission becomes priority 3, a disabled permission becomes OFF, and a missing work-priority map defaults every category to 3. Legacy `light_mood` values migrate to mood; missing recreation state defaults to idle; stale console reservations are reconciled rather than left dangling.

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

This slice intentionally ends at the sealed-wing day-seven survival objective, one deterministic maintenance-hatch pressure event, one aggregate oxygen percentage, one deterministic vault-wide power allocator with brownout shedding, one-seat basic recreation, and one numeric priority for each resident/work-category pair. It does not add resident skills or aptitudes, work speed traits, schedules or shifts, direct-move commands, player-authored job queues, priorities for individual blueprints or recipes, work zones, relationships, social recreation, memories, room beauty, comfort, recreation variety, wiring, circuits, batteries, fuel, spatial gas cells, multiple gases, diffusion, pressure zones, oxygen pipe networks, multiple independently sealed rooms, a sealed-door/room graph, or any other full atmosphere model. It also does not add surface expeditions, caravans, factions, research, mods, multiplayer, IAP, ads, analytics, final art or audio, mobile export, store packaging, raiders, enemies, weapons, combat, or repeated/procedural incidents.
