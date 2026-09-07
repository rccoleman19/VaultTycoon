# PR: Slice 3 — vault air pressure

## Summary

This change extends Vault Tycoon's Godot 4.7.2 desktop colony-survival prototype with one shared, vault-wide oxygen percentage. A new wing starts at 100% oxygen. Each living resident consumes 0.08 percentage points per simulation second, while each powered Air Recycler restores 0.8 points per second. The new fixture costs 14 salvage, draws 3 power, and receives the highest power-grid priority so life support is served before lumens, Nutrient Stations, and Grow Trays during overload.

The existing deterministic hatch timing and response remain intact: the warning fires at exactly 60 simulation seconds, the hatch opens at exactly 80 seconds if still unsealed, and the urgent automatic patch requires 4 salvage plus 8 seconds of Craft work. An open hatch now vents 2.5 oxygen points per second instead of directly damaging residents. The atmosphere HUD raises a low warning at or below 35%; at or below 15%, every living resident takes 4 health damage per second. Day-seven victory requires at least one survivor, a sealed hatch, and breathable oxygen at or above 15%.

This remains a focused resource layer, not a spatial or full gas simulation. There are no room volumes, gas cells, diffusion, oxygen networks, multiple gases, or sealed-door/room graph. The `feat/vault-air-pressure` branch starts directly from the published Slice 2 commit `ae3aa711`; the Slice 3 PR targets `main` as requested and is not merged by this work. These notes do not claim an export or store package.

## Focused scope

- One vault-wide oxygen value that starts at 100% and remains clamped between 0% and 100%
- Consumption of 0.08 oxygen points per second for each living resident, immediately reflecting deaths
- A buildable Air Recycler costing 14 salvage, using 3 power, restoring 0.8 oxygen points per second while powered, and receiving the highest consumer priority
- A low-air warning at or below 35%, plus 4 health damage per second to every living resident while oxygen is at or below 15%
- Existing hatch timing preserved: warning and first-focus interruption at 60 seconds, opening at 80 seconds, and a 4-salvage/8-second urgent patch
- A 2.5-point-per-second vault oxygen leak while the hatch is open, ending immediately when the hatch is sealed
- A right-HUD atmosphere percentage, net-rate and source breakdown, severity color, breach leak readout, alerts, and a stabilization-checklist entry for a powered recycler
- Day-seven victory gated on survival, a sealed hatch, and oxygen at or above the 15% breathable threshold
- Optional oxygen data inside the existing version-1 snapshot; compatible version-1 saves without it load at the safe 100% full-air default
- Focused documentation and verification coverage only; no export, mobile, store-package, final-art, or final-audio work

## How to review

Use Godot 4.7.2.

```bash
godot --editor --path .
```

Run the project with **F5**, select **BEGIN SHIFT**, then exercise this route:

1. On the opening briefing, confirm the stabilization checklist includes **Power an air recycler**. Begin the shift and verify **VAULT ATMOSPHERE** starts at 100%; with four living residents and no powered recycler, its use and net rate should both reflect 0.32 points per second of consumption.
2. Excavate enough salvage, build a Charge Node, select **AIR $14**, and place an Air Recycler blueprint on carved floor. Confirm normal Haul/Craft work supplies 14 salvage and assembles it, then verify the powered fixture draws 3 power and adds 0.8 points per second of recycling. With four residents, a sealed hatch, and one powered recycler, the net rate is +0.48 points per second until the 100% cap.
3. Create a power overload and confirm the Air Recycler is served before the lumen, Nutrient Station, and Grow Tray. Remove or restore sufficient supply and confirm recycler output and the displayed net oxygen rate update with its powered state.
4. Keep at least 4 salvage and at least one living resident with Haul and Craft enabled, then advance to exactly 60 simulation seconds. Confirm the maintenance-hatch warning pauses immediately, resets speed to 1×, focuses the hatch, and shows the remaining grace period without adding a breach toolbar tool.
5. In one run, let the hatch reach exactly 80 seconds unsealed. Confirm it changes to open and the atmosphere readout adds a 2.5-point-per-second leak until the patch completes. In another run, confirm an urgent Haul job delivers 4 salvage before an urgent Craft job performs the 8-second patch, and that sealing stops the leak immediately.
6. Exercise the exact oxygen boundaries: at or below 35%, confirm the low warning; at or below 15%, confirm every living resident takes 4 health damage per second. Above 15%, oxygen alone must not damage residents. Confirm a resident death reduces subsequent consumption by 0.08 points per second.
7. Select a resident during the hatch response and confirm all work permissions remain reachable. In separate runs, disable Haul, disable Craft, spend below 4 salvage, or make the hatch unreachable; confirm the breach HUD names the applicable blocker.
8. Save and load with non-default oxygen, an in-flight hatch Haul, and partial Craft progress. Confirm oxygen, carrier, salvage, patch progress, clock, powered-recycler state, and other simulation state resume without duplication or loss. Also load a compatible schema-version-1 snapshot without an oxygen payload and confirm it receives the 100% full-air default; a missing optional breach payload should continue to receive its existing safe defaults.
9. Continue until day seven and test the gates independently. Victory must wait while the hatch is open or oxygen is below 15%, then become available once at least one resident remains alive, the hatch is sealed, and oxygen is at least 15%.

For a quicker approach to the trigger and oxygen thresholds, use 3× speed. The first warning must still pause at the exact 60-second threshold and reset speed to 1×; the hatch must remain in its warning phase through 79.9 seconds and open at 80 seconds. A complete survival playthrough still requires active resource, power, and job management.

## Testing status

- Godot 4.7.2 completed a headless editor import/parse and a five-frame runtime boot without script or runtime errors.
- The native suite passes **24 cases / 390 assertions**. Slice 3 coverage includes oxygen initialization and clamping; per-living-resident consumption; powered and unpowered recycler output; highest-priority power allocation; exact low/critical threshold behavior and partial-step suffocation accounting; exact 60/80-second hatch boundaries, including a patch completed at 80 seconds; open-hatch oxygen loss and immediate stop on seal; active, malformed, and legacy oxygen snapshots; saved-win invariant rejection; and player-order plus managed day-seven survival plans.
- A 1280×720 Xvfb/OpenGL smoke rendered the opening briefing, vault-atmosphere meter and rates, right-rail oxygen and breach readouts, and the complete two-row toolbar with **AIR $14**, Save, and Load visible. Mesa llvmpipe was used; missing host audio correctly fell back to Godot's dummy driver.
- No export, store package, signing, notarization, mobile package, network service, analytics, ad SDK, payment SDK, or final art/audio validation was performed.

Reproduction commands (an example local binary path is shown; use `godot` if 4.7.2 is installed on `PATH`):

```bash
GODOT_BIN=/tmp/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
"$GODOT_BIN" --headless --path . --editor --quit
scripts/check.sh "$GODOT_BIN"
```

An extended interactive smoke can additionally exercise low/critical severity colors, the powered-recycler checklist transition, overload changes, hatch focus, and the independent day-seven gates.

## Known limitations

- Oxygen is one aggregate percentage for the entire vault. It has no spatial cells, room volumes, diffusion, multiple gases, pressure zones, oxygen network, or sealed-door/room graph.
- The pressure event remains one scripted maintenance-hatch incident rather than a procedural incident director or combat encounter.
- Placeholder geometry and colors remain; final art, animation, sound, and effects are not part of this slice.
- Job control is permission-based rather than a full priority matrix, schedule system, or direct-move command system.
- The single local save slot has no save browser, migration path beyond schema rejection, cloud sync, or conflict recovery.
- Keyboard and mouse are required. There is no mobile export or touch/safe-area adaptation.
- Balance is first-pass and needs observed full-run tuning, especially recycler timing, power contention, oxygen recovery, food timing, salvage recovery, and breach workload.

## Next steps

1. Record a complete interactive Linux day-seven survival smoke plus oxygen and partial-patch save/load regressions.
2. Tune oxygen/recycler balance from full-run observations while preserving the fixed Slice 3 rules and scope.
3. Add focused coverage for power loss during critical-air recovery and worker death during an in-flight patch.

Surface play, caravans, factions, research, mods, multiplayer, IAP, ads, analytics, store packaging, final art/audio, and mobile export remain out of scope. So do raiders, enemies, weapons, combat, repeated/procedural incidents, spatial gas or pressure zones, oxygen networks, multiple-room sealing, a sealed-door graph, and every other form of full atmosphere simulation.
