# Vault Tycoon

Vault Tycoon is an original underground colony-survival prototype built with Godot 4. A crew of four residents begins inside a sealed vault wing. Dig into the surrounding rock, recover salvage, furnish the new rooms, keep food, rest, light, and power stable, and contain the wing's first maintenance-hatch pressure breach through seven complete in-game days.

This repository contains the first two desktop gameplay slices: the first-playable sealed wing and one deterministic environmental breach. It does not include a surface map, caravans, factions, combat, a full atmosphere simulation, research, multiplayer, mods, monetization, analytics, or store packaging.

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
5. Build bunks for rest and a Charge Node before adding a powered Grow Tray and Nutrient Station. The emergency core alone cannot sustain the full food-and-light loop.
6. Keep Cook enabled for at least one resident. A powered Grow Tray produces raw food; a powered Nutrient Station converts raw food into meals.
7. Keep at least 4 salvage available and leave Haul and Craft enabled for breach response. At 60 simulation seconds, a maintenance-hatch pressure warning pauses the game, resets speed to 1×, and focuses the breach.
8. Resume from the warning and watch the urgent response: a resident with Haul enabled delivers 4 salvage, then a resident with Craft enabled performs the 8-second patch. The right HUD reports the 20-second grace period, patch progress, and any missing salvage, permission, or path blocker.
9. If the grace period expires while the hatch remains open, every living resident loses 2 health per simulation second until the patch is complete. Monitor the roster, alerts, power readout, and need bars, then keep at least one resident alive through all seven days to stabilize the wing.

The simulation starts with 8 meals, 2 raw food, 30 salvage, an emergency core, one lumen, and one Salvage Bay. Digging is part of the economy: each completed rock tile creates 3 salvage that must be hauled. The sustainable power-and-food chain costs more than the starting stock, so expansion is required.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a resident or fixture; place the active order/blueprint |
| Left-drag | Paint Dig or Cancel orders across multiple tiles |
| Right click | Return to Select mode |
| `Esc` | Return to Select mode |
| `E` | Activate Dig |
| `X` | Activate Cancel Designation |
| `W` `A` `S` `D` / arrow keys | Pan the camera |
| Middle-drag | Pan the camera |
| Mouse wheel | Zoom between the supported map limits |
| `F` or `Home` | Center on the selected resident, or on the sealed chamber |
| `Space` | Pause/resume simulation |
| `1` `2` `3` | Set 1×, 2×, or 3× speed and resume |

Build tools and work permissions are available in the HUD. **Cancel** removes dig designations and unfinished blueprints; salvage already delivered to a canceled blueprint is refunded. The maintenance-hatch response creates its own urgent jobs and does not add a toolbar tool: use the right-HUD breach focus control and the existing Haul and Craft permissions.

## Gameplay systems

- **MapGrid:** a 50×36 grid of 24-pixel cells, initially solid rock except for a 12×10 sealed chamber. Only the outer steel boundary is permanently undiggable.
- **Residents and Needs:** four residents track food, rest, light mood, and health. Hunger, exhaustion, prolonged severe darkness, and an unsealed post-grace breach can reduce health to zero.
- **JobSystem:** automatically assigns reachable excavation, rubble hauling, blueprint supply, construction, cooking, and urgent breach-response work according to each resident's Dig, Haul, Craft, and Cook permissions. A hatch patch first needs a 4-salvage Haul job and then an 8-second Craft job. Eating and sleeping interrupt ordinary work when needed.
- **Construction:** bunks cost 8 salvage, lumens 5, Charge Nodes 18, Grow Trays 12, Nutrient Stations 10, and Salvage Bays 4.
- **PowerGrid:** the emergency core supplies 2 power and a completed Charge Node supplies 7. Lumens consume 1, Nutrient Stations 2, and Grow Trays 3. During overload, available power is assigned to lumens, then kitchens, then grow trays.
- **FoodSystem:** a powered Grow Tray yields 1 raw food every 9 simulation seconds. Four seconds of cooking converts 1 raw food into 1 meal, closely matching a four-resident wing's baseline demand.
- **DayCycle:** one game day lasts 40 simulation seconds. Pausing stops the clock; speed controls multiply it. Victory becomes available after 280 simulation seconds, when seven full days have elapsed, and requires the first breach to be sealed.
- **Breach pressure:** one deterministic maintenance-hatch warning begins at 60 simulation seconds. Its first appearance pauses the simulation, resets speed to 1×, and focuses the hatch. The 20-second grace period is harmless; after it expires, an open breach damages every living resident by 2 health per simulation second until sealed.
- **PlayerOrders:** builds the 1280×720 HUD, briefing/checklist, roster, contextual inspector, alerts, tool palette, breach pressure/blocker readout and focus control, and outcome screens in GDScript.
- **SaveLoad:** uses a crash-recoverable temporary-file replacement for one versioned local JSON snapshot and restores the map, residents, fixtures, inventory, jobs, time, camera, breach state, and outcome state. An interrupted replacement preserves a recoverable previous file. Breach data is optional within schema version 1 so earlier compatible snapshots can still load.

The main scene keeps these systems as separate child nodes under `VaultGame`, with `VaultGame` coordinating a fixed 0.1-second simulation tick.

## Local save

Use **SAVE** and **LOAD** in the lower toolbar. The game also checkpoints at the start of each new day and saves the victory state. Loading returns the game in a paused state.

The one-slot save is `user://vault_wing_save.json`. With Godot's default per-project user-data directory, that resolves to:

- Linux: `~/.local/share/godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- macOS: `~/Library/Application Support/Godot/app_userdata/Vault Tycoon/vault_wing_save.json`
- Windows: `%APPDATA%\Godot\app_userdata\Vault Tycoon\vault_wing_save.json`

Deleting or replacing this file resets or overwrites the only local slot. Save schema version 1 rejects malformed or incompatible files rather than partially loading them. Slice 2 keeps schema version 1 and adds optional breach state; a compatible version-1 snapshot without that state receives safe breach defaults instead of being rejected.

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

Extract the macOS ZIP on a Mac and open the contained `.app`. Run `VaultTycoon.exe` on Windows. These are unsigned development builds: operating-system security prompts are expected, and no signing or notarization is configured. If an export produces a companion `.pck`, ship it beside the executable. The entire `exports/` directory is ignored by Git.

Cross-exporting creates the target files when the matching templates are installed, but final smoke testing should happen on each target operating system. macOS signing/notarization and Windows code signing are deliberately outside this slice.

## Later mobile export path

Mobile is a later adaptation, not a current supported target. Before adding Android or iOS presets, the interaction layer needs explicit touch support: tap selection, a confirmed placement gesture, pinch zoom, two-finger or edge pan, alternatives for right/middle click and keyboard shortcuts, 48-dp minimum targets, safe-area-aware panels, and a compact or collapsible inspector. Hover-only tooltips need tap-accessible equivalents, and accidental painting while panning must be prevented. The simulation should also be profiled on mobile hardware.

After that UI work:

- **Android:** install the matching templates, OpenJDK, and Android SDK; configure their paths in Godot; add an Android preset with a unique package identifier; and export a local debug APK for device testing. Do not create or upload a store AAB in this slice.
- **iOS:** on macOS with Xcode installed, add an iOS preset and bundle identifier, export an Xcode project, and run a development-signed build on a connected device or simulator. Do not archive, notarize, or submit a store build in this slice.

The existing GL Compatibility renderer and canvas-item stretch mode are suitable starting points, but they do not replace touch UX, aspect-ratio, performance, and safe-area validation.

## Scope boundary

This slice intentionally ends at the sealed-wing day-seven survival objective and contains exactly one deterministic maintenance-hatch pressure event. It does not add raiders, enemies, weapons, combat, repeated or procedural incidents, pressure zones, oxygen networks, room-sealing simulation, or any other full atmosphere model. Surface expeditions, caravans, faction diplomacy, a research tree, mods, multiplayer, IAP, ads, analytics SDKs, and store packaging remain out of scope.
