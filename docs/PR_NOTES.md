# PR: Slice 4 — power brownouts

## Summary

This change extends Vault Tycoon's Godot 4.7.2 desktop prototype with explicit power-grid supply, demand, served-load, disabled-load, and brownout accounting. Completed enabled consumers now have deterministic fixed-priority allocation. When enabled demand exceeds supply, the grid records and displays every shed load and emits brownout/recovery transitions.

Air Recyclers remain protected at the highest fixed priority, ahead of Lumens, Nutrient Stations, and Grow Trays. They still go offline when available supply cannot satisfy their 3-power demand. A severe brownout can therefore remove recycler oxygen output and cascade into the existing Slice 3 low-air and suffocation danger.

Players can recover by selecting a completed consumer and disabling its demand, removing a non-core completed fixture for a 50% salvage refund, or building another Charge Node for 7 additional power. Disabled consumers can be re-enabled; the emergency core cannot be removed.

## Focused Scope

- Explicit power accounting for supply, enabled demand, served load, disabled demand, shed demand, and shed fixture count
- Deterministic power allocation by fixed fixture-kind priority, then building id
- Protected allocation order: Air Recycler, Lumen, Nutrient Station, Grow Tray
- Exact shed order: Grow Trays -> Nutrient Stations -> Lumens -> Air Recyclers
- Same-priority tie break: newer fixtures shed before older fixtures
- Brownout transition messages and right-HUD power-grid state
- Selected-fixture controls for consumer disable/enable and non-core deconstruction recovery
- Save/load support for manually disabled consumers while preserving compatible schema-one defaults
- Breach warning modal regression fix: speed hotkeys 1/2/3 no longer acknowledge or dismiss the modal
- Prior Slice 1-3 behavior and the PR #1 BUG-1..BUG-6 fixes remain in scope and covered by the prior suites
- No merge, export, store package, signing, mobile package, network service, analytics, ads, payment SDK, final art, or final audio work

## How To Review

Use Godot 4.7.2.

```bash
godot --editor --path .
```

Run the project with **F5**, select **BEGIN SHIFT**, then exercise this route:

1. Build a Charge Node, Air Recycler, Nutrient Station, and Grow Tray. Confirm the right HUD reports supply 9, demand 9, served 9, and all enabled consumers served.
2. Add another Grow Tray. Confirm the grid enters brownout, the newest Grow Tray is shed first, and the HUD names the shed load.
3. Confirm the exact shed order: Grow Trays, then Nutrient Stations, then Lumens, then Air Recyclers; newer fixtures shed first within a fixture kind.
4. Select the shed Grow Tray. Confirm its inspector says **SHED · BROWNOUT**, identifies its fixed low priority, and offers **DISABLE** and **REMOVE** controls.
5. Disable that optional load. Confirm disabled demand is reported separately and the brownout clears immediately, even while paused.
6. Re-enable it, then remove a non-core fixture. Confirm half its salvage cost is refunded and the grid recalculates immediately. Confirm the emergency core cannot be removed.
7. Remove or otherwise lose Charge Node capacity while an Air Recycler is present. Confirm the recycler can brown out when only the 2-power emergency core remains, oxygen recycling drops to 0.0, and existing oxygen danger resumes.
8. Build another Charge Node. Confirm brownout clears, the recycler comes back online, and oxygen recovery resumes.
9. Save and load with a disabled consumer. Confirm disabled state, derived powered flags, and brownout state restore deterministically. Also confirm schema-one snapshots without manual-disable fields default consumers to enabled.

## Testing Status

- `scripts/check.sh` passes with Godot 4.7.2.
- The native suite passes **31 cases / 531 assertions**, plus the focused breach-warning speed-key regression run from `scripts/check.sh`.
- Slice 4 coverage includes balanced-grid accounting, deterministic fixed shed order, paused recovery controls, shed production pause/resume, recycler protection, an overbuild-to-recycler-loss oxygen cascade, disable/deconstruct/add-capacity recovery, disabled-state save/load, and legacy power defaults.
- Prior Slice 1-3 suites still cover scene boot, controls, dig/build/cancel jobs, food, oxygen, breach timing/response, save/load atomicity, unmanaged loss, player-order survival, and managed day-seven victory.
- No export, store package, signing, notarization, mobile package, network service, analytics, ad SDK, payment SDK, or final art/audio validation was performed.

Reproduction:

```bash
scripts/check.sh
```

## Known Limitations

- Power is still a vault-wide resource allocator, not a wiring, circuit, battery, or fuel simulation.
- Brownouts do not damage fixtures; they only deny powered behavior while demand is shed.
- Deconstruction is instant and returns a fixed 50% salvage value for non-core completed fixtures.
- Placeholder geometry and colors remain; final art, animation, sound, and effects are not part of this slice.
- Keyboard and mouse are required. There is no mobile export or touch/safe-area adaptation.

## Next Steps

1. Record a complete interactive Linux day-seven smoke with a deliberate brownout and recovery.
2. Tune balance around power contention, recycler timing, oxygen recovery, food timing, salvage recovery, and breach workload.
3. Add focused coverage for worker death during an in-flight patch.

Surface play, caravans, factions, research, mods, multiplayer, IAP, ads, analytics, store packaging, final art/audio, and mobile export remain out of scope. So do raiders, enemies, weapons, combat, repeated/procedural incidents, spatial gas or pressure zones, oxygen networks, multiple-room sealing, a sealed-door graph, and every other form of full atmosphere simulation.
