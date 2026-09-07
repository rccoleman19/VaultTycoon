# PR: First-playable sealed vault wing

## Summary

This change bootstraps Vault Tycoon as an original Godot 4.7.2 desktop colony-survival prototype. A new game starts paused with four residents sealed in a small underground chamber. The player excavates rock, hauls the resulting salvage, places and constructs fixtures, assigns work permissions, and balances meals, rest, lighting mood, and electrical load. Keeping at least one resident alive through seven complete in-game days produces the victory state.

The presentation uses a distinct industrial vault-control language—residents, seal stabilization, Charge Nodes, Lumens, Nutrient Stations, and Salvage Bays—and placeholder vector/Node2D visuals. No third-party game IP or assets are included.

## Landed scope

- Godot 4.7.2 project configured for a 1280×720 desktop reference viewport and GL Compatibility rendering
- One 50×36 sealed underground wing with a 12×10 starting chamber, dig designations, progressive excavation, pathfinding, and an undiggable steel boundary
- Four starting residents with food, rest, light-mood, health, movement, selection, death, and survival-behavior states
- Autonomous Dig, Haul, Craft, and Cook work with per-resident permission toggles, job reservation, reachability checks, and survival interruptions
- Salvage economy driven by excavated rubble, blueprint delivery, construction work, and refunds for canceled unfinished blueprints
- Bunks, Lumens, Charge Nodes, Grow Trays, Nutrient Stations, and Salvage Bays with costs, power demand/output, and contextual status
- Working power and food loops with overload priority, powered crop production, ingredient conversion, meal consumption, and starvation pressure
- Day clock, pause and three simulation speeds, daily checkpoints, all-residents-lost failure, and seven-full-day victory
- In-game briefing/checklist, roster, needs inspector, work controls, resource/power HUD, alerts, build/order toolbar, and win/loss panels
- One-slot, versioned local JSON save/load covering the wing and current simulation state
- Linux, macOS, and Windows development export presets plus source-run/export/mobile-follow-up documentation

## How to review

Use Godot 4.7.2 with matching export templates.

```bash
godot --editor --path .
```

Run the project with **F5**, select **BEGIN SHIFT**, then exercise this route:

1. Select a resident and toggle a work permission off and on.
2. Designate adjacent rock and confirm a resident excavates it.
3. Confirm rubble is hauled and increases salvage.
4. Place bunks and watch Haul/Craft jobs complete them.
5. Add a Charge Node, Grow Tray, and Nutrient Station; verify the power readout and food production/cooking loop.
6. Save, alter the wing, load, and confirm the saved map, residents, resources, buildings, jobs, clock, and camera return with simulation paused.
7. Continue until either all residents die or day seven completes; verify the appropriate paused outcome screen and checkpoint action.

For a quicker logic exercise, use 3× speed. A complete survival playthrough still requires active resource and job management.

## Testing status

- Godot 4.7.2 headless editor import/parse completed successfully with exit code 0, including project initialization and loading of the configured main scene and local GDScript dependencies.
- The native headless suite passes **9 cases / 107 assertions**. It covers the configured scene and UI, sealed-map invariants, real excavation work, blueprint supply/construction, overload recovery, exact day-seven timing, save/load deterministic continuation and malformed-snapshot rejection, an untouched-wing loss, a player-issued dig/build survival plan, and a managed win.
- An Xvfb/OpenGL visual smoke ran successfully through Mesa llvmpipe at 1280×720, and the captured opening briefing/HUD was inspected. The main scene also completed a separate five-frame headless runtime boot without script/runtime errors.
- Desktop export presets load in the Godot 4.7.2 editor, and a Linux-preset `--export-pack` resource build completed successfully with exit code 0. Standalone platform binaries were not produced because matching export templates are not installed in this workspace; Linux, macOS, and Windows artifacts still need native-host smoke tests before a release build.
- No store build, signing, notarization, mobile package, network service, analytics, ad SDK, or payment SDK was exercised or introduced.

Reproduction commands (the workspace download is shown; use `godot` if 4.7.2 is installed on `PATH`):

```bash
GODOT_BIN=/tmp/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
"$GODOT_BIN" --headless --path . --editor --quit
scripts/check.sh "$GODOT_BIN"
mkdir -p exports/linux
"$GODOT_BIN" --headless --path . --export-pack "Linux" /tmp/vault-tycoon-validation.pck
```

## Known limitations

- Placeholder geometry and colors stand in for final art, animation, sound, music, and effects.
- The slice contains one fixed wing and four fixed starting residents; there is no procedural scenario selection or broader world.
- Job control is permission-based rather than a full priority matrix, schedule system, or direct-move command system.
- Power is modeled as one wing-wide capacity pool rather than spatial wiring, batteries, fuel, switching, or multiple circuits.
- Food is a compact grow-and-cook loop without recipes, crop choice, spoilage, refrigeration, or nutrition variety.
- Beds are selected automatically when residents rest and are not manually assigned.
- The single local save slot has no save browser, migration path beyond schema rejection, cloud sync, or conflict recovery.
- Keyboard and mouse are required. The fixed-density HUD has not been adapted for touch, handheld safe areas, ultrawide layouts, or small screens.
- Export presets are unsigned development outputs. Platform signing, notarization, installers, achievements, and storefront metadata are absent.
- Balance is first-pass and needs observed full-run tuning, especially food timing, salvage recovery, workload contention, and accelerated-time warning clarity.

## Next steps

1. Run and record a complete Linux day-seven survival smoke test plus save/load regression on Godot 4.7.2.
2. Tune the starting inventory, need decay, production rates, construction costs, and job priorities from full-run observations so both survival and failure remain legible.
3. Add focused automated coverage for snapshot round trips, seven-day boundary behavior, job cancellation/reservation, power overload ordering, and food conversion.
4. Improve order feedback for unreachable work, insufficient salvage, unpowered producers, and inactive permissions; add accessible non-color-only cues.
5. Add original vault art, animation, audio, and effects while retaining the current system boundaries and terminology.
6. Smoke-test unsigned desktop exports on Linux, macOS, and Windows and document host-specific issues.
7. Prototype a touch-specific input/HUD layer and device performance pass before adding local Android/iOS development presets. Do not package or submit stores.

Surface expeditions, caravans, faction diplomacy, research, mods, multiplayer, IAP, ads, analytics SDKs, and store packaging remain explicitly out of scope for these follow-ups.
