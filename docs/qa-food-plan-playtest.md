# QA: food plan playtest, sublevel 05 seed 8 (2026-10-30)

Build: `13ce9c51` (feat/food-plan-card-fit). This is hand-written; Codex was unavailable. No game code was changed.

Run: one plain run with no follow driver. The driver calls begin_shift and sets 2x at frame 25, then presses resume 75 frames after the breach warning. There is no other input. Godot 4.7.2, `--fixed-fps 30`, 1280x720, opengl3.
The event log matches the earlier headless plain log at the same sim line for line (`diff` is empty). Result: Dax dies of starvation at sim 202.0 s on day 6/7 (frame 3133). Meals were 0 and salvage 35 at the time.

Times are game-sim seconds from shift start.

## 1. Sim 23.6 s, day 1: the card says to save salvage while Next says to build food

- **On screen:** Next reads "food runway short · YOU place a Nutrient Station · THEY cook". The food plan card under it is greyed out and reads "Keep 4 salvage for the hatch". Salvage 30, meals 11 (2.8 days), and Nutrient Station costs $10.
- **Why it's bad:** The two top lines in the sidebar pull in opposite directions. Salvage 30 covers the hatch (4) and the station (10) with room left over. A new player reads "keep salvage" as "don't spend" and builds nothing. This is the moment the run is lost.
- **PNG:** `docs/clips/2026-10-30/qa-playtest-1-held-card-d1-2026-10-30.png`

## 2. Sim 132.8 s, day 4: Bo is starving and the card offers a plan the player can't afford

- **On screen:** Next reads "Bo starving · YOU place a Nutrient Station · THEY cook". Meals 0 (0.0 days), salvage 26. The card is enabled and reads "Charge + Station + Tray · 40". The alerts are "DARKNESS · 2 CREW UNLIT +3 more", "BED SHORTAGE", "NO REC CONSOLE" and a day-4 cache prompt.
- **Why it's bad:** The only clickable food action costs 40 with 26 in the bank. The $10 station that Next asks for is not offered as a single step. Starvation also shares the stack with four lower-priority alerts, so the urgent item doesn't stand out.
- **PNG:** `docs/clips/2026-10-30/qa-playtest-2-bo-starving-d4-2026-10-30.png`

## 3. Sim 202.0 s, day 6: Dax dies with 35 salvage unspent, and the card suggests a Rec Console

- **On screen:** The RESIDENT LOST modal reads "Dax died of starvation", with "This would have saved Dax: … place a Nutrient Station". Behind it the card still reads "Charge + Station + Tray · 40". A second line reads "Spend 35: build Rec Console". Salvage 35, meals 0.
- **Why it's bad:** The recap names a $10 fix the player could have afforded for the whole run. Meanwhile the food card points at a non-food purchase while people starve. The first death feels unfair rather than instructive.
- **PNG:** `docs/clips/2026-10-30/qa-playtest-3-dax-dies-d6-2026-10-30.png`
