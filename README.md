# Vault Tycoon

Vault Tycoon is an original underground colony-survival prototype built with Godot 4. A crew of four residents begins inside a sealed vault wing. Dig into the surrounding rock, recover salvage, furnish the new rooms, keep food, rest, mood, power, and shared oxygen stable, and contain the wing's first maintenance-hatch pressure breach through seven complete in-game days.

This repository contains the first seven desktop gameplay slices: the first-playable sealed wing, one deterministic environmental breach, one vault-wide oxygen percentage, deterministic power brownouts with priority shedding, per-resident mood with basic powered recreation, a crew-wide work priorities board, and first-session balance and help polish. Oxygen and power are deliberately vault-wide resources rather than spatial gas or wiring simulations. The project does not include a surface map, caravans, factions, combat, research, mods, multiplayer, IAP, ads, analytics, store packaging, final art or audio, mobile export, a medical system, a multi-room sealed-door graph, or any other full atmosphere simulation.

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
6. Build and power **GROW $12** and **NUTRI $10**. Keep Cook above OFF for at least one resident: the Grow Tray produces raw food and the powered Nutrient Station converts 1 raw food into 1 meal.
7. Keep at least 4 salvage uncommitted and keep at least one living resident's Haul and Craft above OFF. At exactly 60 simulation seconds, the maintenance-hatch warning pauses the shift, resets speed to 1×, focuses the hatch, and interrupts recreation.
8. Choose **RESUME RESPONSE**. Emergency work overrides numeric work ranks: an eligible hauler delivers the 4-salvage patch and an eligible crafter completes 8 seconds of patch work. The hatch opens at the exact 80-second boundary if the patch is unfinished, then vents 2.5 oxygen points per second until sealed.
9. Optionally build **REC $8**. A Rec Console supports mood but is not required to win. The core and one Charge Node supply 9 power, exactly consumed by the starting Lumen, Grow Tray, Nutrient Station, and Air Recycler; disable the Lumen or build another Charge Node to serve the console's additional 1-power load. At 35 mood or below, a resident seeks a powered free console and recovers to 85.
10. Optionally press **P** or choose **PRIORITIES [P]** to specialize ordinary work. Every resident starts at priority 3 for Dig, Haul, Craft, and Cook. A cell cycles `1 → 2 → 3 → 4 → OFF → 1`; 1 is highest, 4 is lowest, and OFF disables that category for that resident. Hatch work still overrides numbered ranks, but OFF remains a hard permission boundary.
11. Keep at least one resident alive, seal the hatch, and finish seven full days with oxygen at or above 15%. If day seven completes before both final gates are satisfied, the HUD identifies whether the hatch or oxygen is still blocking victory.

The simulation starts with 12 meals, 4 raw food, 48 salvage, 100% oxygen, an emergency core, one Lumen, and one Salvage Bay. Twelve excavations add 36 recoverable salvage, bringing the critical-route pool to 84: enough for two bunks, one Charge Node, one Grow Tray, one Nutrient Station, one Air Recycler, and the 4-salvage hatch patch, with 10 salvage left for one recoverable mistake. A 15-tile expansion brings the pool to 93 and leaves 7 salvage after adding the optional Rec Console and patching the hatch. Expansion is still required, and an untouched wing still fails before day seven.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a resident or fixture; repeated clicks cycle stacked residents and an occupied fixture; place the active order/blueprint |
| Left-drag | Paint Dig or Cancel orders across multiple tiles |
| Right click | Return to Select mode |
| `Esc` | Close reopened Help or the priorities board if open; otherwise return to Select mode |
| `E` | Activate Dig |
| `X` | Activate Cancel Designation |
| `P` | Open or close the crew work priorities board |
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

Build tools, Help, and the work priorities board are available in the HUD. Right-click or press **Esc** to return to Select mode; press **X** when you intend to activate Cancel. **P** toggles the board, the roster's **PRIORITIES** action opens it, and **CLOSE** or **Esc** dismisses it. Opening or editing the board does not change the current pause state, speed, selection, or map tool. Opening **HELP** pauses behind the checklist; **CLOSE** or **Esc** restores the simulation's prior running or paused state. Help has no keyboard shortcut. The active tool's instructions return after transient placement, warning, and error messages expire. The Air Recycler uses **AIR $14** and the Rec Console uses **REC $8**; neither has a keyboard shortcut. Selecting a completed consumer shows its fixed power priority and lets you disable or re-enable it; any completed non-core fixture can be removed for a 50% salvage refund. **Cancel** removes dig designations and unfinished blueprints; salvage already delivered to a canceled blueprint is refunded. The maintenance-hatch response creates its own urgent jobs and does not add a toolbar tool: use the right-HUD breach focus control and keep Haul and Craft above OFF.

## Gameplay systems

- **MapGrid:** a 50×36 grid of 24-pixel cells, initially solid rock except for a 12×10 sealed chamber. Only the outer steel boundary is permanently undiggable.
- **Residents and Needs:** four residents track food, rest, overall mood, and health. Awake mood loses 18 points per day from baseline strain, plus 30 in darkness, 12 each while hungry or exhausted, and 24 while vault oxygen is at or below 35%. Low mood slows work; critical mood triggers a costly unstructured stress break, and prolonged severe mood can damage health. Each living resident consumes 0.08 oxygen percentage points per simulation second and takes 4 health damage per second while oxygen is at or below 15%.
- **JobSystem:** automatically assigns reachable excavation, rubble hauling, blueprint supply, construction, cooking, and urgent breach-response work according to each resident's numeric Dig, Haul, Craft, and Cook priority. OFF excludes a work category; among ordinary available work, priority 1 is considered before 2, then 3, then 4. Residents with the best available priority claim first, with resident ID as the deterministic worker tie-break; each resident then retains the existing job-kind, distance, and job-ID tie-breaks. A hatch patch first needs a 4-salvage Haul job and then an 8-second Craft job. Emergency hatch work always outranks ordinary work regardless of its numeric Haul or Craft priority, but OFF still blocks that category. Eating, sleeping, and recreation interrupt ordinary work when needed; urgent breach response preempts recreation.
- **Construction:** bunks cost 8 salvage, lumens 5, Charge Nodes 18, Grow Trays 12, Nutrient Stations 10, Salvage Bays 4, Air Recyclers 14, and Rec Consoles 8.
- **PowerGrid:** the emergency core supplies 2 power and a completed Charge Node supplies 7. Lumens and Rec Consoles consume 1, Nutrient Stations 2, and Grow Trays and Air Recyclers 3. The HUD reports supply, enabled demand, served power, disabled demand, and any brownout shed load. Brownouts shed the lowest-priority enabled consumers first in this exact fixed order: Rec Consoles, Grow Trays, Nutrient Stations, Lumens, then Air Recyclers. Within a fixture kind, newer fixtures shed before older fixtures. Air Recyclers are always protected at the highest priority, but still go offline when available supply cannot satisfy their 3-power demand; that removes recycler output and can cascade into oxygen danger. Players can recover by disabling optional consumers, removing non-core fixtures for partial salvage, or adding Charge Node capacity.
- **Mood and recreation:** recreation is autonomous self-care rather than a work permission. At 35 mood or below, a resident deterministically chooses the nearest reachable, powered, unoccupied Rec Console, with building ID as the tie-breaker. Mood recovers only after the resident reaches it, at 18 points per simulation second, until exactly 85. One console has one seat. Hunger, sleep, loss of power, deconstruction, death, and the pressure warning all release the reservation safely. Passive mood drain pauses during sleep and active console use.
- **FoodSystem:** starts with 12 meals, 4 raw food, and 48 salvage. A powered Grow Tray yields 1 raw food every 9 simulation seconds. Four seconds of cooking at a powered Nutrient Station converts 1 raw food into 1 meal, closely matching a four-resident wing's baseline demand.
- **OxygenSystem:** tracks one shared percentage for the entire vault, starting at 100% and clamped from 0% to 100%. Living residents consume 0.08 points per second each, every powered Air Recycler restores 0.8 points per second, and an open hatch vents 2.5 points per second. The low threshold is 35%; at or below the 15% critical threshold, all living residents take 4 health damage per second.
- **DayCycle:** one game day lasts 40 simulation seconds. Pausing stops the clock; speed controls multiply it. Victory becomes available after 280 simulation seconds, when seven full days have elapsed, and requires at least one living resident, a sealed hatch, and breathable oxygen at or above 15%.
- **Breach pressure:** one deterministic maintenance-hatch warning begins at exactly 60 simulation seconds. Its first appearance pauses the simulation, resets speed to 1×, and focuses the hatch. The hatch opens at exactly 80 seconds if the 4-salvage, 8-second patch is unfinished; while open, it adds a 2.5-point-per-second oxygen loss until sealed.
- **PlayerOrders:** builds the 1280×720 HUD, reopenable Help/checklist, roster and adjacent **PRIORITIES [P]** control, contextual inspector, alerts, lower map/build/save toolbar including **AIR $14**, **REC $8**, and **HELP**, the complete crew-by-work priority board, power supply/demand/brownout readouts, every living resident's mood, active mood factors, fixed-priority fixture labels and recovery controls, vault-atmosphere meter and rate breakdown, breach pressure/blocker readout and focus control, day-seven victory blockers, and outcome screens in GDScript. The checklist distinguishes the required powered food and air chain from optional recreation and work specialization.
- **SaveLoad:** uses a crash-recoverable temporary-file replacement for one versioned local JSON snapshot and restores the map, residents, per-category work priorities, fixtures (including manually disabled power loads), inventory, jobs, time, camera, breach state, oxygen, mood/recreation state, and outcome state. An interrupted replacement preserves a recoverable previous file. Slice 7 remains on schema version 1: numeric priorities are an optional compatible extension, older boolean work permissions migrate to priority 3 or OFF, earlier `light_mood` snapshots migrate to canonical mood, and missing recreation state defaults safely.

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

Slice 7 does not apply a recent-damage mood modifier because the current resident model has no damage-recency timer or saved history.

## Local save

Use **SAVE** and **LOAD** in the lower toolbar. The game also checkpoints at the start of each new day and saves the victory state. Loading returns the game in a paused state.

The one-slot save is `user://vault_wing_save.json`. With Godot's default per-project user-data directory, that resolves to:

- Linux: `~/.local/share/godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- macOS: `~/Library/Application Support/Godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- Windows: `%APPDATA%\Godot\app_userdata\Vault Tycoon\vault_wing_save.json`

Deleting or replacing this file resets or overwrites the only local slot. Save schema version 1 rejects malformed or incompatible files rather than partially loading them. Slice 7 keeps schema version 1: breach, oxygen, per-fixture manual-disable state, canonical mood, active recreation state, and numeric work priorities remain compatible extensions. New saves retain the legacy boolean permission map alongside the numeric map. A legacy enabled permission becomes priority 3, a disabled permission becomes OFF, and a missing work-priority map defaults every category to 3. Legacy `light_mood` values migrate to mood; missing recreation state defaults to idle; stale console reservations are reconciled rather than left dangling.

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

The script uses an isolated temporary user-data directory and runs every checked suite: headless editor import, the core gameplay suite, mood/recreation suite, work-priorities suite, breach-modal speed-key regression, and a five-frame main-scene boot. A successful run ends with `All Vault Tycoon headless checks passed.`

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

Slice 7 intentionally polishes the existing sealed-wing day-seven survival objective rather than adding another major system. The boundary remains one deterministic maintenance-hatch pressure event, one aggregate oxygen percentage, one deterministic vault-wide power allocator with brownout shedding, one-seat basic recreation, and one numeric priority for each resident/work-category pair. It does not add resident skills, aptitudes, or passions, work speed traits, schedules or shifts, direct-move commands, player-authored job queues, priorities for individual blueprints or recipes, work zones, relationships, social recreation, memories, room beauty, comfort, recreation variety, a medical system, wiring, circuits, batteries, fuel, spatial gas cells, multiple gases, diffusion, pressure zones, oxygen pipe networks, multiple independently sealed rooms, a sealed-door/room graph, or any other full atmosphere model. It also does not add surface expeditions, caravans, factions, research, mods, multiplayer, IAP, ads, analytics, final art or audio, mobile export, store packaging, raiders, enemies, weapons, combat, or repeated/procedural incidents.


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
