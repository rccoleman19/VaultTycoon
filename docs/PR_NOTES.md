# PR: Slice 2 — first breach pressure

## Summary

This change extends Vault Tycoon's original Godot 4.7.2 desktop colony-survival prototype with its first external pressure event. A new game still starts paused with four residents in a sealed underground chamber, and the player still excavates rock, recovers salvage, builds fixtures, assigns work permissions, and balances meals, rest, lighting mood, and electrical load. At exactly 60 simulation seconds, one deterministic maintenance hatch reports a pressure breach, pauses the simulation, resets speed to 1×, and focuses the incident.

The breach has a 20-second grace period. Its urgent automatic response uses the existing work model: a resident with Haul enabled delivers 4 salvage, then a resident with Craft enabled completes an 8-second patch. If the grace period expires first, the open breach damages every living resident by 2 health per simulation second until sealed. The right HUD exposes pressure, patch progress, exact blockers, and a focus action. There is no new toolbar tool, combat system, or full atmosphere simulation.

This branch is stacked on `feat/first-playable-vault-wing`. The new PR targets `main` as requested, so its comparison includes PR #1 until that first-playable branch lands; after PR #1 merges, the comparison narrows to this breach-pressure change.

## Focused scope

- One deterministic maintenance-hatch breach at exactly 60 simulation seconds, with first-warning auto-pause, 1× reset, and camera focus
- A 20-second no-damage grace period followed by 2 health damage per simulation second to every living resident while the breach remains open
- Urgent automatic breach jobs that consume 4 salvage through Haul, then require 8 seconds of Craft work to seal the hatch
- A visible, selectable hatch marker; pressure/progress/blocker readouts; breach-first alerts; focused warning action; and a scroll-safe permission rail at 1280×720
- Day-seven victory gated on both survival and a sealed hatch, while the existing unmanaged starvation loss remains intact
- Version-1 snapshot compatibility with strict breach-state validation, deterministic in-flight emergency hauling, accumulator reset, and crash-recoverable file replacement
- Focused README, review notes, and deterministic headless coverage; no export or store-package work

## How to review

Use Godot 4.7.2.

```bash
godot --editor --path .
```

Run the project with **F5**, select **BEGIN SHIFT**, then exercise this route:

1. Keep at least 4 salvage and at least one living resident with Haul and Craft enabled, then advance to exactly 60 simulation seconds. Confirm the maintenance-hatch warning pauses immediately, resets speed to 1×, focuses the hatch, and shows a 20-second grace countdown without adding a toolbar tool.
2. Resume and confirm an urgent Haul job delivers 4 salvage before an urgent Craft job performs the 8-second patch. Verify pressure and patch progress remain visible and the sealed confirmation clears the active danger.
3. Select a resident during the response. Confirm the right rail brings all four work permissions into view and the breach remains reachable through its focus action.
4. In separate runs, disable Haul, disable Craft, spend below 4 salvage, or make the hatch unreachable; confirm the HUD names the applicable blocker.
5. Leave the breach open beyond the grace period and confirm each living resident loses 2 health per simulation second only while it remains open. Seal it and confirm damage stops immediately.
6. Save and load during the in-flight Haul and partial Craft stages. Confirm the carrier, salvage, patch progress, clock, and other simulation state resume without duplication or loss. Also load a compatible schema-version-1 snapshot without breach data and confirm safe defaults.
7. Continue until day seven; verify victory waits for both a living resident and a sealed hatch. An untouched wing should still lose from starvation after automatically containing the breach.

For a quicker approach to the trigger, use 3× speed. The first warning must still pause at the exact threshold and reset speed to 1× before the grace period can advance. A complete survival playthrough still requires active resource and job management.

## Testing status

- Godot 4.7.2 completed a headless editor import/parse and a five-frame runtime boot without script or runtime errors.
- The native suite passes **19 cases / 296 assertions**. It retains the first-slice coverage and adds hatch reservation, exact 59.9/60/79.9/80-second boundaries, one-shot pause/focus interruption, breach-first alerts, urgent-job ordering and blockers, exact patch work, prepared no-damage containment, open-breach damage, immediate damage stop, clock-consistent state validation, legacy hatch-fixture compatibility, deterministic in-flight hauling, active and legacy save/load, interrupted-write recovery, preserved unmanaged loss, and the sealed-only day-seven win gate.
- An Xvfb/OpenGL smoke rendered the warning, focused Resume action, visible hatch marker, compound breach alerts, active Haul response, and the selected-resident permission rail at 1280×720 through Mesa llvmpipe. The rail scrolls and automatically reveals all four work permissions without overlapping the map or bottom toolbar.
- No export, store package, signing, notarization, mobile package, network service, analytics, ad SDK, or payment SDK was introduced or exercised.

Reproduction commands (the workspace download is shown; use `godot` if 4.7.2 is installed on `PATH`):

```bash
GODOT_BIN=/tmp/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
"$GODOT_BIN" --headless --path . --editor --quit
scripts/check.sh "$GODOT_BIN"
```

## Known limitations

- Placeholder geometry and colors stand in for final breach art, animation, sound, and effects.
- Breach pressure is one scripted maintenance-hatch incident, not a procedural incident director, combat encounter, spatial pressure model, oxygen network, or room-sealing simulation.
- Job control is permission-based rather than a full priority matrix, schedule system, or direct-move command system.
- The single local save slot has no save browser, migration path beyond schema rejection, cloud sync, or conflict recovery.
- Keyboard and mouse are required. The HUD has not been adapted for touch, handheld safe areas, ultrawide layouts, or small screens.
- Balance is first-pass and needs observed full-run tuning, especially food timing, salvage recovery, breach workload/damage, and job contention.

## Next steps

1. Run and record a complete interactive Linux day-seven survival smoke plus a partial-patch save/load regression.
2. Tune breach damage and urgent-job priority from full-run observations so both recovery and failure remain legible.
3. Add focused coverage for worker death or permission changes during an in-flight patch.
4. Replace placeholder presentation only when an original art/audio pass is separately scoped.

Raiders, enemies, weapons, combat, repeated or procedural incidents, pressure zones, oxygen networks, room-sealing simulation, and any other full atmosphere model remain out of scope. Surface expeditions, caravans, faction diplomacy, research, mods, multiplayer, IAP, ads, analytics SDKs, and store packaging also remain explicitly out of scope for these follow-ups.
