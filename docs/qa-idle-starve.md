# QA: the idle player still starves (05 s8, Dax, day 6, 202 s)

Docs only. No game code was changed. This note was written by hand (Codex is unavailable).
- Evidence: the plain idle runs at `food-card-next-step-engineer/m/head_*_plain.log`, recorded on f7f7de75. The sim matches #135 (66743504), because the later commits on that branch only touch tests and docs.
- Driver: `plain_driver.gd` with PT_MODE=idle, 9000 frames at fixed-fps 30. It takes no player taps after begin_shift.
- Earlier diagnosis: [qa-d8-idle-diagnosis.md](qa-d8-idle-diagnosis.md).

## The problem
A player who never taps still loses a resident. #134 and #135 made the sidebar honest:
- the Food plan card offers "Nutrient Station · 10";
- Next says "YOU place a Nutrient Station";
- STARVING leads the alert line.

But every one of those is a request to the player, so an idle player ignores all of them. On 05 s8 the crew seals the hatch by itself, sits on 26–35 unspent salvage, and starves anyway.

### Evidence (05 s8 plain log)
| Sim time | What the log shows |
|---|---|
| 23.6 s | `NEXT = Next: food runway short · YOU place a Nutrient Station · THEY cook`. The card reads "Nutrient Station · 10" and is enabled, with 30 salvage. |
| 58.7 s | `FIRST BREACH CONTAINED`: the crew patched the hatch without input. |
| 132.8 s (D4) | `NEXT = Next: Bo starving · YOU place a Nutrient Station · THEY cook`; `ALERT = STARVING: Bo · +4 more`. The HUD shows MEALS 0, RAW 4, SALVAGE 26. |
| 145.3 s | `NEXT = Next: Dax starving · YOU place a Nutrient Station · THEY cook`. |
| 202.0 s (D6) | `STATUS = Dax has died. Review the death recap.` The recap reads: "This would have saved Dax: Dax starving · YOU place a Nutrient Station · THEY cook". Salvage is 35, and the Spend nudge on #135 read "Spend 35: build Rec Console". #136 fixes that nudge. |
| END | `reason=death outcome=death sim=202.0 day=6`. |

Same seed, follow driver (taps what Next says): `outcome=win sim=280.0 day=7 alive=Ari,Bo,Cyra,Dax`. All 6 plain runs die of starvation on D4–D6 (03: 157.5–175.2 s; 05: 197.5–202.2 s). All 6 follow runs win.

### Root cause
- The automation can dig, haul, patch and cook, but it never places a fixture.
- Food production stays at 0 for the whole run: no Grow Tray, no Station, and the 4 starting raw are never cooked.
- The 12 starting meals are the only food.
- From qa-d8, a Station alone at frame 30 changes nothing, because it is unpowered. Charge + Station on 05 trades starvation for suffocation on D3–4. Charge + Station + Grow Tray solves food on 03.

So any fix has to place a powered food chain without breaking air.

## Option 1: the Cook auto-queues the food card's step when food is short
When the food runway is short or someone is starving, the hatch is sealed, and the food card has an affordable step with nothing food-related queued, the Cook places a blueprint for the card's step. That is the same build Next and Spend name. It places at most one blueprint at a time and costs the same salvage.
- **Keeps the challenge:**
  - It only fires once food is already short, so an idle wing still loses meals and mood and gets a worse grade.
  - It spends the salvage the player would otherwise steer, so there is less left for Rec, bunks or air.
  - An engaged player acts earlier and better.
- **Tradeoffs:**
  - Players may read it as "the game plays itself".
  - Auto-placement needs a placement rule (nearest free floor to the pantry), which can block a planned Annex. It has to respect `annex_waiting_for_room()`.
  - qa-d8 shows the order matters on 05: Charge + Station without enough air kills by oxygen. The auto step must follow the card's power-aware order (Charge only when the Tray needs power), and it must be checked against the air budget.
  - It changes the sim, so every ladder row can move.
- **Test:**
  - Unit tests: auto-queue fires only under (short or starving) and sealed and affordable and nothing queued; it never fires pre-seal or when the step is unaffordable; it places the same kind the card shows.
  - Plain 6-run matrix: 05 s8 should survive to D7, or at least die later and not of starvation. Report the cause and time of death per run.
  - Follow must stay 6/6. Run the 48-game ladder and justify every changed row; idle3 rows will change.
  - A mutant that ignores the card's order should fail.

## Option 2: a hold-to-confirm "Food plan" default, chosen at the briefing
Add a briefing toggle, "Crew builds food when it runs short" (default off for 03/05 and on for 01–02). When it is on, Option 1's rule runs. When it is off, nothing auto-builds; instead, after 20 s of STARVING with an affordable food step, the card pulses and the recap says how many seconds the step sat affordable ("Station was affordable for 69 s").
- **Keeps the challenge:**
  - Harder levels still need the player.
  - Idle play on easy levels survives.
  - The recap teaches the player instead of saving them.
- **Tradeoffs:**
  - It adds a setting and a save field (`version` bump; legacy saves default to off).
  - Two behaviours per level double the test matrix.
  - It does not fix the reported 05 idle death unless the default is on for 05.
- **Test:**
  - Save/load round-trip of the toggle.
  - With the toggle off, plain logs are byte-identical to today (proves zero sim change).
  - With the toggle on, run the plain 6-run matrix and the ladder as in Option 1.
  - A recap test: an "affordable for N s" line appears only when a food step was affordable while someone was STARVING.

## Recommendation
Option 1 is the smaller change and directly answers "idle starves". Ship it behind Option 2's toggle only if Directors want 03/05 to stay hard for idle players. Either way, first gate it on the power- and air-aware order from the card, because qa-d8 shows a bare Station or Charge + Station can make 05 worse.
