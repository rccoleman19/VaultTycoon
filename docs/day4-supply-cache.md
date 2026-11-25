# Day-4 supply cache

A seed-selected rock hex on the south edge of the starting chamber contains a
sealed supply cache (with a west-edge fallback if pockets fill the south edge).
Selection uses its own seed salt and skips generated floor pockets, leaving the opening layout and its twelve-rock objective unchanged.
Until Day 4 (120 simulation seconds), the cache hex is sealed and cannot be dug
or claimed. It remains rock when the seal releases: no floor or inventory drops in.

On Day 4 the cache is marked and a single, cancellable Dig designation is queued.
This default salvage task lets an otherwise untouched wing benefit, while the
player can cancel it, disable Dig/Haul, or spend that worker's time elsewhere.
The crew must walk to the face, perform the normal eight units of excavation,
and reach the newly opened hex on a normal rubble-haul job. Only that arrival
claims the cache: tuned to **6 salvage and 2 prepared meals**, once.
Ordinary rock rubble still needs its usual return haul and pays separately.

One latched informational alert in DETAILS names the coordinates, contents and
Dig/Haul requirement. It stays present through claim, with identical wording;
Next has no new selector state. A static gold cache marker remains until claim.
The alert latch, claimed flag, version and position are saved under the additive
`day4_supply_cache` key. Dig progress and rubble jobs use existing save fields.
Loads restore these states without re-announcing, re-queuing canceled work, or
repaying the reward. Older saves without the key retain their previous behavior.

This buys a little food runway and material, not a food loop, life support,
bunks or a seal win. Dig and Haul permissions, travel, excavation and competing
urgent jobs all apply. The player can abandon the expedition, and doing so loses
its benefit. Plain wings must still die; tuning is checked with the Director's
individual plain and follow-the-Next runs.

## Tuning and verification

The initial four-meal candidate made the 03/4242 plain run win at 280.0 s and
was rejected. One meal left 03/8's death at its baseline 272.8 s and was also
rejected. Two meals preserves deaths while extending all three tested 03 seeds.

Godot 4.7.2 runs are isolated, one process at a time. Plain runs use the supplied
playtest driver (05 idle, no relay; 03 engaged, Relay Lumen). Follow runs use the
supplied follow driver with those same settings. Every run has a 9000-frame cap.
No ladder, full matrix, or `scripts/check.sh` is run.

Final plain-run results (seconds):

| Sublevel | Seed | Baseline death | Cache death | Day | Outcome |
| --- | ---: | ---: | ---: | ---: | --- |
| 03 | 4242 | 268.2 | 277.5 | 7 | death |
| 03 | 8 | 272.8 | 277.5 | 7 | death |
| 03 | 1234 | 268.2 | 272.8 | 7 | death |
| 05 | 4242 | 188.2 | 197.5 | 5 | death |
| 05 | 8 | 192.6 | 202.0 | 6 | death |
| 05 | 1234 | 188.2 | 202.2 | 6 | death |

All six follow runs won at 280.0 s with no deaths (four survivors on 05,
five on 03). Their `followed` counts were 18/16/16 on 05 and 10/11/13 on 03
for seeds 4242/8/1234.

Exact final-run END lines (driver frame/time prefixes omitted):

```text
03/4242 plain: END reason=death outcome=death sim=277.5 outcome_frame=2935 outcome_sim=277.5 day=7
03/8 plain: END reason=death outcome=death sim=277.5 outcome_frame=2935 outcome_sim=277.5 day=7
03/1234 plain: END reason=death outcome=death sim=272.8 outcome_frame=2888 outcome_sim=272.8 day=7
05/4242 plain: END reason=death outcome=death sim=197.5 outcome_frame=3066 outcome_sim=197.5 day=5
05/8 plain: END reason=death outcome=death sim=202.0 outcome_frame=3133 outcome_sim=202.0 day=6
05/1234 plain: END reason=death outcome=death sim=202.2 outcome_frame=3136 outcome_sim=202.2 day=6
03/4242 follow: END reason=win outcome=win sim=280.0 outcome_frame=2960 outcome_sim=280.0 day=7 alive=Ari,Bo,Cyra,Dax,Fen deaths={  } followed=10
03/8 follow: END reason=win outcome=win sim=280.0 outcome_frame=2960 outcome_sim=280.0 day=7 alive=Ari,Bo,Cyra,Dax,Fen deaths={  } followed=11
03/1234 follow: END reason=win outcome=win sim=280.0 outcome_frame=2960 outcome_sim=280.0 day=7 alive=Ari,Bo,Cyra,Dax,Fen deaths={  } followed=13
05/4242 follow: END reason=win outcome=win sim=280.0 outcome_frame=4303 outcome_sim=280.0 day=7 alive=Ari,Bo,Cyra,Dax deaths={  } followed=18
05/8 follow: END reason=win outcome=win sim=280.0 outcome_frame=4303 outcome_sim=280.0 day=7 alive=Ari,Bo,Cyra,Dax deaths={  } followed=16
05/1234 follow: END reason=win outcome=win sim=280.0 outcome_frame=4303 outcome_sim=280.0 day=7 alive=Ari,Bo,Cyra,Dax deaths={  } followed=16
```

The seed-4242, 1200-frame Next-entry counts are unchanged: **05 = 8**
(engaged, no relay) and **03 = 11** (engaged, relay; first 1200 frames of its
plain run). Both match the Director's clip baselines. The 05 idle opening has
3 entries, also below its budget.

Final solo test results:

| Suite | Cases | Assertions | Failures | Script errors |
| --- | ---: | ---: | ---: | ---: |
| Day-4 cache | 6 | 177 | 0 | 0 |
| Next flicker | 17 | 1948 | 0 | 0 |
| Alert triage | 14 | 318 | 0 | 0 |
| Save atomicity | 128 | 1021 | 0 | 0 |
| Food hauling | 9 | 237 | 0 | 0 |
| Wing layout | 9 | 79 | 0 | 0 |
| Late-shift goals | 3 | 287 | 0 | 0 |
| Total | 186 | 4067 | 0 | 0 |

The exact new test file and its imported UID were overlaid on a `git archive
1e9fafe2` control inside this worktree. It exited 1: **6 cases, 6 assertions,
6 expected failures, 0 script errors**. The final implementation exits 0:
**6 cases, 177 assertions, 0 failures, 0 script errors**.

The test UID was generated with Godot's `--headless --path . --import`.
Layout and late-shift results above use their clean serial reruns after an
accidental brief overlap of those two suites. All reported playtests ran serially.
No commit was made.
