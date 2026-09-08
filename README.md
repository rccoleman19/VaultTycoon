# Vault Tycoon

Vault Tycoon is an original underground colony-survival prototype built with Godot 4. A crew of four residents begins inside a sealed vault wing. Dig into the surrounding rock, recover salvage, furnish the new rooms, keep food, rest, light, power, and shared oxygen stable, and contain the wing's first maintenance-hatch pressure breach through seven complete in-game days.

This repository contains the first four desktop gameplay slices: the first-playable sealed wing, one deterministic environmental breach, one vault-wide oxygen percentage, and deterministic power brownouts with priority shedding. Oxygen and power are deliberately vault-wide resources rather than spatial gas or wiring simulations. The project does not include a surface map, caravans, factions, combat, research, mods, multiplayer, IAP, ads, analytics, store packaging, final art or audio, mobile export, a multi-room sealed-door graph, or any other full atmosphere simulation.

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

1. Select a resident from the map or roster and verify their work permissions.
2. Choose **DIG** or press **E**, then click or drag across rock connected to carved floor by adjacent dig designations. Residents with Dig enabled excavate the reachable front of that chain.
3. Excavated rubble becomes salvage after a resident hauls it to the Salvage Bay.
4. Place blueprints only on carved floor. Residents with Haul and Craft enabled supply and assemble them.
5. Build a Charge Node, then choose **AIR $14** and assemble an Air Recycler on carved floor. It uses 3 power, receives the grid's highest fixed consumer priority, and restores 0.8 oxygen percentage points per simulation second while powered. The 2-power emergency core cannot run the recycler without added capacity.
6. Build bunks for rest and add a powered Grow Tray and Nutrient Station for food. Keep Cook enabled for at least one resident; the tray produces raw food and the station converts raw food into meals.
7. Watch **VAULT ATMOSPHERE** in the right HUD. Oxygen starts at 100%, and each living resident consumes 0.08 percentage points per simulation second. The HUD shows the current percentage, net rate, resident use, recycler output, and active hatch leak; it warns at or below 35% and becomes critical at or below 15%.
8. Keep at least 4 salvage available and leave Haul and Craft enabled for breach response. At exactly 60 simulation seconds, a maintenance-hatch pressure warning pauses the game, resets speed to 1×, and focuses the breach.
9. Resume from the warning and watch the urgent response: a resident with Haul enabled delivers 4 salvage, then a resident with Craft enabled performs the 8-second patch. The right HUD reports the grace period through the exact 80-second opening boundary, patch progress, and any missing salvage, permission, or path blocker.
10. If the hatch reaches 80 seconds unsealed, it opens and vents another 2.5 oxygen points per simulation second until patched. At or below 15% oxygen, every living resident takes 4 health damage per simulation second. To win after seven full days, keep at least one resident alive, seal the hatch, and finish with at least 15% oxygen.

The simulation starts with 8 meals, 2 raw food, 30 salvage, an emergency core, one lumen, and one Salvage Bay. Digging is part of the economy: each completed rock tile creates 3 salvage that must be hauled. The sustainable power, oxygen, and food chain costs more than the starting stock, so expansion is required.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a resident or fixture; place the active order/blueprint |
| Left-drag | Paint Dig or Cancel orders across multiple tiles |
| Right click | Return to Select mode |
| `Esc` | Return to Select mode |
| `E` | Activate Dig |
| `X` | Activate Cancel Designation |
| Bottom build buttons | Place the selected fixture blueprint on carved floor; **AIR $14** selects the Air Recycler |
| `W` `A` `S` `D` / arrow keys | Pan the camera |
| Middle-drag | Pan the camera |
| Mouse wheel | Zoom between the supported map limits |
| `F` or `Home` | Center on the selected resident, or on the sealed chamber |
| `Space` | Pause/resume simulation |
| `1` `2` `3` | Set 1×, 2×, or 3× speed and resume |

Build tools and work permissions are available in the HUD. The Air Recycler uses the **AIR $14** build button and has no keyboard shortcut. Selecting a completed consumer shows its fixed power priority and lets you disable or re-enable it; any completed non-core fixture can be removed for a 50% salvage refund. **Cancel** removes dig designations and unfinished blueprints; salvage already delivered to a canceled blueprint is refunded. The maintenance-hatch response creates its own urgent jobs and does not add a toolbar tool: use the right-HUD breach focus control and the existing Haul and Craft permissions.

## Gameplay systems

- **MapGrid:** a 50×36 grid of 24-pixel cells, initially solid rock except for a 12×10 sealed chamber. Only the outer steel boundary is permanently undiggable.
- **Residents and Needs:** four residents track food, rest, light mood, and health. Hunger, exhaustion, prolonged severe darkness, and critical vault oxygen can reduce health to zero. Each living resident consumes 0.08 oxygen percentage points per simulation second and takes 4 health damage per second while oxygen is at or below 15%.
- **JobSystem:** automatically assigns reachable excavation, rubble hauling, blueprint supply, construction, cooking, and urgent breach-response work according to each resident's Dig, Haul, Craft, and Cook permissions. A hatch patch first needs a 4-salvage Haul job and then an 8-second Craft job. Eating and sleeping interrupt ordinary work when needed.
- **Construction:** bunks cost 8 salvage, lumens 5, Charge Nodes 18, Grow Trays 12, Nutrient Stations 10, Salvage Bays 4, and Air Recyclers 14.
- **PowerGrid:** the emergency core supplies 2 power and a completed Charge Node supplies 7. Lumens consume 1, Nutrient Stations 2, Grow Trays 3, and Air Recyclers 3. The HUD reports supply, enabled demand, served power, disabled demand, and any brownout shed load. Brownouts shed the lowest-priority enabled consumers first in this exact fixed order: Grow Trays, Nutrient Stations, Lumens, then Air Recyclers. Within a fixture kind, newer fixtures shed before older fixtures. Air Recyclers are always protected at the highest priority, but still go offline when available supply cannot satisfy their 3-power demand; that removes recycler output and can cascade into oxygen danger. Players can recover by disabling optional consumers, removing non-core fixtures for partial salvage, or adding Charge Node capacity.
- **FoodSystem:** a powered Grow Tray yields 1 raw food every 9 simulation seconds. Four seconds of cooking converts 1 raw food into 1 meal, closely matching a four-resident wing's baseline demand.
- **OxygenSystem:** tracks one shared percentage for the entire vault, starting at 100% and clamped from 0% to 100%. Living residents consume 0.08 points per second each, every powered Air Recycler restores 0.8 points per second, and an open hatch vents 2.5 points per second. The low threshold is 35%; at or below the 15% critical threshold, all living residents take 4 health damage per second.
- **DayCycle:** one game day lasts 40 simulation seconds. Pausing stops the clock; speed controls multiply it. Victory becomes available after 280 simulation seconds, when seven full days have elapsed, and requires at least one living resident, a sealed hatch, and breathable oxygen at or above 15%.
- **Breach pressure:** one deterministic maintenance-hatch warning begins at exactly 60 simulation seconds. Its first appearance pauses the simulation, resets speed to 1×, and focuses the hatch. The hatch opens at exactly 80 seconds if the 4-salvage, 8-second patch is unfinished; while open, it adds a 2.5-point-per-second oxygen loss until sealed.
- **PlayerOrders:** builds the 1280×720 HUD, briefing/checklist, roster, contextual inspector, alerts, tool palette including **AIR $14**, power supply/demand/brownout readouts, fixed-priority fixture labels and recovery controls, vault-atmosphere meter and rate breakdown, breach pressure/blocker readout and focus control, and outcome screens in GDScript. The checklist explicitly tracks a powered Air Recycler.
- **SaveLoad:** uses a crash-recoverable temporary-file replacement for one versioned local JSON snapshot and restores the map, residents, fixtures (including manually disabled power loads), inventory, jobs, time, camera, breach state, oxygen, and outcome state. An interrupted replacement preserves a recoverable previous file. Breach, oxygen, and manual-disable payloads are optional within schema version 1 so earlier compatible snapshots still load with safe defaults.

The main scene keeps these systems as separate child nodes under `VaultGame`, with `VaultGame` coordinating a fixed 0.1-second simulation tick.

## Local save

Use **SAVE** and **LOAD** in the lower toolbar. The game also checkpoints at the start of each new day and saves the victory state. Loading returns the game in a paused state.

The one-slot save is `user://vault_wing_save.json`. With Godot's default per-project user-data directory, that resolves to:

- Linux: `~/.local/share/godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- macOS: `~/Library/Application Support/Godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- Windows: `%APPDATA%\Godot\app_userdata\Vault Tycoon\vault_wing_save.json`

Deleting or replacing this file resets or overwrites the only local slot. Save schema version 1 rejects malformed or incompatible files rather than partially loading them. Slice 4 keeps schema version 1: breach, oxygen, and per-fixture manual-disable state are optional; compatible legacy snapshots receive safe breach defaults, full air when oxygen is absent, and enabled power consumers when manual-disable state is absent.

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

This slice intentionally ends at the sealed-wing day-seven survival objective, one deterministic maintenance-hatch pressure event, one aggregate oxygen percentage, and one deterministic vault-wide power allocator with brownout shedding. It does not add wiring, circuits, batteries, fuel, spatial gas cells, multiple gases, diffusion, pressure zones, oxygen pipe networks, multiple independently sealed rooms, a sealed-door/room graph, or any other full atmosphere model. It also does not add surface expeditions, caravans, factions, research, mods, multiplayer, IAP, ads, analytics, final art or audio, mobile export, store packaging, raiders, enemies, weapons, combat, or repeated/procedural incidents.
