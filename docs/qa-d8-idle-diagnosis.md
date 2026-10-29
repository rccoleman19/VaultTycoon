# QA-d #8: idle diagnosis ("default automation starves by day 6")

Diagnosis only. No game code was changed. Base: a6a0d005 (0d7d5761 + #132; #132 only touches the follow driver and docs, so the game code is the same as 0d7d5761).
- Plain runs: the existing hand rerun in `post-seal-air-tip-engineer/g/head_*_plain*` (plain_driver.gd, PT_MODE=idle, 9000 frames, fixed-fps 30, one Godot at a time).
- Counterfactuals: `qa-d8/cf_driver.gd`, which is the plain driver plus one early player act at frame 30. Logs are in `qa-d8/`.

## Verdict
The report is right. The cause is not slow automation: **with no player input, nothing that makes food is ever built.**
- The crew stays busy and seals the hatch on its own, by sim 59–81s.
- But in all 6 runs the only buildings are Emergency Core, Lumen and Salvage Bay.
- Food production is exactly 0 for the whole run. The 12 starting meals are the only food: they run out on day 3–4, and a resident starves to death on day 4–6.

## Per-run results (plain, no input after begin_shift + speed 2)
| Run | Death (sim s / day) | Victim | Cause | Sealed at | Unspent salvage |
|---|---|---|---|---|---|
| 03 s4242 | 175.2 / D5 | Fen | starvation (food 0 → health 0) | 80.5 | 44–53 |
| 03 s8 | 162.0 / D5 | Dax | starvation | 58.7 | 44–53 |
| 03 s1234 | 157.5 / D4 | Cyra | starvation | 63.7 | 44–53 |
| 05 s4242 | 197.5 / D5 | Cyra | starvation | 78.7 | 26–35 |
| 05 s8 | 202.0 / D6 | Dax | starvation | 58.7 | 26–35 |
| 05 s1234 | 202.2 / D6 | Dax | starvation | 63.7 | 26–35 |

## Food curve (same shape in all 6 runs)
- Production: 0 meals and 0 raw. There is no Grow Tray and no Nutrient Station. The 4 starting raw are never cooked.
- Consumption:
  - 03 has 5 residents and burns 12 meals in about 100–120s.
  - 05 has 4 residents and burns 12 meals in about 130s.
- 05 s1234 sampled every 20s: meals 12,12,8,7,4,3,1,0 (at t=140, D4), then 0.
- Resident food then falls to 0, health drains to 0, and the first death comes 30–60s later.
- Rest and mood also collapse to about 9–20, but those don't kill.
- From about t=40 on, Next says "food runway short · YOU place a Nutrient Station · THEY cook", then "X starving · …". The player is told what to do; the idle player never does it.

## Counterfactuals (one scripted act at frame 30, same seeds)
| Act | 03 (s4242 / s8 / s1234) | 05 (s4242 / s8 / s1234) |
|---|---|---|
| none (plain) | D5 / D5 / D4 starvation | D5 / D6 / D6 starvation |
| K: Nutrient Station only (what Next asks for) | **identical to plain**, 175.2 / 162.0 / 157.5 | **identical**, 197.5 / 202.0 / 202.2 |
| C+K: Charge Node + Station | 202.0 / 202.0 / 202.2 (D6), starvation delayed | **worse**: 129.9 / 112.4 / 116.8 (D3–4), oxygen |
| C+K+G: + Grow Tray | 232.6 / 237.2 / 237.2 (D6), **food solved**, dies of suffocation | 129.9 / 112.4 / 117.1 (D3), oxygen |

What the counterfactuals show:
1. **The Next tip's single action doesn't work.**
   - Base supply is 2. Lumen uses 1 and a Nutrient Station needs 2, so the Station is browned out ("SHED Nutrient Station") and the run is byte-for-byte the same as plain.
   - The real first step is power (Charge Node), and the tip doesn't say so.
2. **Charge Node + Station + Grow Tray (one early action of 3 placements) fixes food on 03.** The residents then live until the post-seal air wall: "Ari suffocating · YOU begin reclamation · THEY fund the Air Recycler", death on D6 at about 235s. So in 03 the actions that prevent the starvation death are (1) C+K+G early, and (2) begin reclamation for the Air Recycler. I didn't test (2); it's a separate, already-tipped step.
3. **On 05 (salvage 30), spending on the food chain makes things worse.**
   - C+K uses the salvage the crew would have spent on the hatch patch.
   - The breach opens at about 65–70s and oxygen kills on D3.
   - So in 05 the order matters: patch first (the crew does this alone), then food. Placing food at frame 30 is the wrong timing; after the seal the salvage is 26–35, which is still enough for C+K. I didn't run "food after seal".

## Levers (up to two; idle-friendly, not auto-winning)
**L1: a one-tap "Food plan" card**, like the comfort card.
- When food runway is short and there is no food production, offer one tap that queues the full working chain: Charge Node (only if power can't cover it), Nutrient Station, and Grow Tray.
- It holds back the hatch-patch reserve: it doesn't fund until the seal is done, or until salvage is at least reserve + cost.
- Light touch: one tap turns starvation into a working food loop.
- Not auto-win: air and reclamation still need the player (03 C+K+G still dies on D6 of air).
- Follow 6/6 and the ladder: the card needs a tap, and neither the plain/idle3 drivers nor b3-lq ever tap it, so the NONE and B3 idle rows can't move. The follow driver acts on Next text, not cards, so it's unaffected as long as Next text doesn't change.
- Verify with the 6/6 follow rerun + ladder rerun, which should be byte-identical END lines.

**L2: an honest food tip** (copy and gating only, no new mechanics).
- When placing a Nutrient Station would be browned out, Next should say "YOU place a Charge Node · then Station" (or show the shed cost).
- Before the seal, drop the food tip below the patch while salvage is less than patch reserve + station cost.
- This fixes the trap in the K row and the 05 oxygen regression for players who do follow the tip.
- Risk: the follow driver parses Next. It already handles power through `_enable_or_power` and wins 6/6, but any change to Next text has to be gated on a full follow 6/6 rerun and the ladder. If either moves, ship L1 alone.

Rejected: passive food (raw trickle or auto-cook without a station). It would make idle viable but changes the idle3 NONE and B3 ladder rows directly, and it starts to look like auto-play.
