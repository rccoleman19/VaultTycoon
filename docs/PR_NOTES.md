# PR: Slice 5 — colonist mood and basic recreation

## Summary

This change extends Vault Tycoon's Godot 4.7.2 desktop prototype with a deterministic overall mood need and autonomous basic recreation. Awake residents now lose mood from baseline shift strain, darkness, hunger, exhaustion, and low vault oxygen. Low mood reduces work speed; critically low mood still causes disruptive stress breaks and can eventually damage health.

Players can build an 8-salvage Rec Console. At 35 mood or below, a resident interrupts ordinary work, reserves the nearest reachable free console, walks to it, and recovers mood only while physically present. Each powered console serves one resident at a time and releases them at exactly 85 mood. Recreation requires no work permission.

Rec Consoles consume 1 power at the new fixed OPTIONAL priority. They shed before Grow Trays, Nutrient Stations, Lumens, and Air Recyclers, keeping food production and life support protected. A shed or disabled console immediately releases its user. The pressure-hatch response also cancels recreation and stress breaks so eligible residents can claim urgent Haul or Craft work.

## Focused Scope

- Canonical per-resident mood from 0–100, with deterministic awake modifiers
- Mood-state and active-factor readouts in the resident inspector
- Existing low-mood work penalty, severe-mood health damage, and stress-break fallback
- One-tile Rec Console blueprint, cost, construction, deconstruction, drawing, and inspector state
- Autonomous recreation with exact seek and completion thresholds
- Nearest-path selection, building-ID tie-break, and one-resident console capacity
- No remote recovery while a resident is still walking
- Lowest-priority 1-power recreation load and immediate brownout/disable recovery behavior
- Hunger, rest, death, deconstruction, and breach-response interruption cleanup
- Save/load support for canonical mood and active recreation reservations
- Schema-one compatibility with prior `light_mood` snapshots and missing recreation fields
- HUD build control, powered-console checklist item, explicit mood in every living resident row, crew summary, active factors, and low-mood alerts
- Prior Slice 1–4 behavior and breach-warning modal regression remain in scope
- No relationships, traits, memories, schedules, social simulation, recreation variety, final art, or final audio

## Balance Contract

- Mood range and starting value: 0–100, starting at 72 for every resident
- Awake baseline mood: -18 points per 40-second day
- Darkness: an additional -30 points per day
- Food below 35: an additional -12 points per day
- Rest below 30: an additional -12 points per day
- Vault oxygen at or below 35%: an additional -24 points per day
- Fully stacked awake pressure: -96 points per day
- Sleeping and physically active console use: passive mood loss is suspended
- Waking from unbedded floor sleep: -12 mood once
- Mood below 30: 0.70× work multiplier; all combined need penalties retain a 0.35 floor
- HUD tiers: STEADY at 70+, STRAINED at 40–69.999, STRESSED above 9 and below 40, BREAK RISK at 9 or lower
- Recreation seek threshold: mood at or below 35
- Rec Console recovery: +18 mood per simulation second while on the console cell
- Recreation completion: exactly 85 mood
- Critical fallback: mood at or below 9 starts a 7-second unstructured stress break that grants 8 mood
- Severe mood: mood at or below 5 costs 5 health per day
- Rec Console: 8 salvage, 5-second assembly, 1 power, OPTIONAL priority, one user

There is no recent-damage mood modifier in Slice 5 because the current runtime and schema do not track when damage occurred.

## How To Review

Use Godot 4.7.2.

```bash
godot --editor --path .
```

Run the project with **F5**, select **BEGIN SHIFT**, then exercise this route:

1. Select each resident and confirm every roster row shows **MOOD**, while the inspector shows the mood state, current factors, and work speed.
2. Build a Rec Console with **REC $8**. With only the emergency core and starting lumen, confirm both 1-power loads are served.
3. Let a resident reach 35 mood. Confirm they reserve the console, walk to it without recovering remotely, then use it until mood reaches 85.
4. Lower two residents' mood with one console available. Confirm only one uses it; the other can claim it after the first leaves.
5. Lower vault oxygen to 35%. Confirm an awake lit resident's inspector reports **low O2** and **-42 mood/day**: -18 baseline plus -24 low oxygen.
6. Build the regular Charge Node, Air Recycler, Grow Tray, and Nutrient Station. At 10 demand against 9 supply, confirm only the OPTIONAL Rec Console sheds.
7. Add another Charge Node or disable an optional competing load. Confirm the console powers up and a low-mood resident can seek it again.
8. Disable or remove an occupied console. Confirm recreation stops immediately, its reservation clears, and removal refunds 4 salvage.
9. Trigger the maintenance-hatch warning while a resident is recreating. Confirm the console is released immediately and urgent Haul/Craft response takes priority after resuming.
10. Save during a walk to recreation or an active console session, then load. Confirm the one-seat reservation, mood, position, power allocation, and continued simulation restore deterministically.
11. Load a compatible schema-one snapshot containing `light_mood` but no Slice 5 recreation fields. Confirm its value becomes mood and the resident safely defaults to no recreation target.

## Testing Status

- `scripts/check.sh` runs the import check, the full native regression suite, focused mood/recreation coverage, the breach-warning speed-key regression, and a boot smoke.
- Godot 4.7.2 final result: native suite **31 cases / 541 assertions**; focused mood/recreation suite **9 cases / 231 assertions**; breach-modal speed-key regression and five-second boot smoke passed.
- Focused coverage includes exact mood rates and bounds, threshold inclusivity, console fixture/power priority, no remote or unpowered recovery, occupied-console brownout cleanup, deterministic selection and capacity, hunger/rest/death interruption, the critical fallback break, HUD states, breach preemption, and active/legacy/malformed save states.
- Prior Slice 1–4 suites continue to cover scene boot, controls, dig/build/cancel jobs, food, oxygen, breach timing/response, power allocation and recovery, save/load atomicity, unmanaged loss, player-order survival, and managed day-seven victory.
- A live 1280×720 GL Compatibility smoke checked the briefing, two-row toolbar, per-resident mood rows, low-O2 factor text, mood bars, active recreation feedback, and Rec Console inspector.
- No export, store package, signing, notarization, mobile package, network service, analytics, ad SDK, payment SDK, or final art/audio validation was performed.

Reproduction:

```bash
scripts/check.sh
```

## Known Limitations

- Mood is one aggregate need, not a thought, memory, trait, relationship, beauty, comfort, or social system.
- The Rec Console provides one generic activity and one seat. There is no recreation variety or tolerance.
- Recreation is autonomous; there are no player-authored schedules or manual resident commands.
- A resident whose console becomes unavailable resumes other behavior and waits until still at or below the seek threshold before choosing another.
- Placeholder resident mood bars, console power states, and active-recreation pulses are included; final art, animation polish, and sound are not.
- Recent damage does not affect mood because the prototype has no damage-recency state yet.
- Keyboard and mouse are required. There is no mobile export or touch/safe-area adaptation.

## Next Steps

1. Record a complete interactive Linux day-seven smoke with a deliberate recreation brownout and recovery.
2. Tune mood decay, console throughput, power contention, and construction timing against the seven-day route.
3. Consider richer mood modifiers only after the basic recreation loop is stable and legible.

Surface play, caravans, factions, research, mods, multiplayer, IAP, ads, analytics, store packaging, final art/audio, and mobile export remain out of scope. So do relationships, social simulation, traits, memories, schedules, recreation variety, raiders, enemies, weapons, combat, repeated/procedural incidents, spatial gas or pressure zones, oxygen networks, multiple-room sealing, and a sealed-door graph.
