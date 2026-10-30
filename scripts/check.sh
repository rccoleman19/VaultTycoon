#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${1:-${GODOT_BIN:-/tmp/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64}}"
TEST_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vault-tycoon-headless.XXXXXX")"
COLD_ROOT=""
# Headroom for long headless suites (survival-next ~48s solo; flaked at 60s under load).
GODOT_CHECK_TIMEOUT="120s"

cleanup() {
	rm -rf -- "$TEST_DATA_DIR"
	if [[ -n "${COLD_ROOT}" ]]; then
		rm -rf -- "$COLD_ROOT"
	fi
}
trap cleanup EXIT

if [[ ! -x "$GODOT_BIN" ]]; then
	echo "Godot executable not found or not executable: $GODOT_BIN" >&2
	exit 127
fi

run_godot_check() {
	local label="$1"
	shift
	local log_file="$TEST_DATA_DIR/${label}.log"
	if ! XDG_DATA_HOME="$TEST_DATA_DIR" timeout "$GODOT_CHECK_TIMEOUT" "$GODOT_BIN" --headless --path "$PROJECT_ROOT" "$@" 2>&1 | tee "$log_file"; then
		echo "Godot ${label} check failed." >&2
		return 1
	fi
	if grep -E -q 'SCRIPT ERROR:|Parse Error:|Failed to load script|Invalid call\.' "$log_file"; then
		echo "Godot ${label} check logged a script/runtime error." >&2
		return 1
	fi
}

cd "$PROJECT_ROOT"

run_godot_check import --editor --quit
# Mid-game salvage sink (QA 2026-10-18c #3, slice 1).
run_godot_check midgame-upgrade --script res://tests/test_midgame_upgrade.gd
run_godot_check wing-orders --script res://tests/test_wing_orders.gd
run_godot_check post-seal-pacing --script res://tests/test_post_seal_pacing.gd
run_godot_check post-seal-air-tip --script res://tests/test_post_seal_air_tip.gd
run_godot_check idle-start --script res://tests/test_idle_start.gd
run_godot_check postseal-help --script res://tests/test_postseal_help.gd
run_godot_check mk2-air-gate --script res://tests/test_mk2_air_gate.gd
run_godot_check mk2-fit-gate --script res://tests/test_mk2_fit_gate.gd
run_godot_check keep-running --script res://tests/test_keep_running.gd
run_godot_check keep-running-food --script res://tests/test_keep_running_food.gd
run_godot_check annex --script res://tests/test_annex.gd
run_godot_check annex-payoff --script res://tests/test_annex_payoff.gd
run_godot_check annex-room --script res://tests/test_annex_room.gd
run_godot_check comfort --script res://tests/test_comfort.gd
run_godot_check feast --script res://tests/test_feast.gd
run_godot_check kr-wellbeing --script res://tests/test_kr_wellbeing.gd
run_godot_check sidebar-reach --script res://tests/test_sidebar_reach.gd
run_godot_check bed-alert --script res://tests/test_bed_alert.gd
run_godot_check tests --script res://tests/test_runner.gd
run_godot_check save-snapshot-atomic --script res://tests/test_save_snapshot_atomic.gd
run_godot_check hatch-timing-save --script res://tests/test_hatch_timing_save.gd
run_godot_check mood-recreation --script res://tests/test_mood_recreation.gd
run_godot_check meal-runway --script res://tests/test_meal_runway.gd
run_godot_check frugal-meal-estimate --script res://tests/test_frugal_meal_estimate.gd
run_godot_check food-plan-card --script res://tests/test_food_plan_card.gd
run_godot_check food-card-next-step --script res://tests/test_food_card_next_step.gd
run_godot_check spend-nudge-food-first --script res://tests/test_spend_nudge_food_first.gd
run_godot_check cook-auto-food-step --script res://tests/test_cook_auto_food_step.gd
run_godot_check air-early-warning --script res://tests/test_air_early_warning.gd
run_godot_check air-codex-fixes --script res://tests/test_air_codex_fixes.gd
run_godot_check stress-break-venting --script res://tests/test_stress_break_venting.gd
run_godot_check rec-boost --script res://tests/test_rec_boost.gd
run_godot_check work-priorities --script res://tests/test_work_priorities.gd
run_godot_check work-tie-help-text --script res://tests/test_work_tie_help_text.gd
run_godot_check breach-modal-speed-keys --script res://tests/test_breach_modal_speed_keys.gd
run_godot_check next-tip-warning --script res://tests/test_next_tip_warning.gd
run_godot_check next-urgency-rank --script res://tests/test_next_urgency_rank.gd
run_godot_check spend-agrees-next --script res://tests/test_spend_agrees_next.gd
run_godot_check alert-triage --script res://tests/test_alert_triage.gd
run_godot_check alert-priority --script res://tests/test_alert_priority.gd
run_godot_check hatch-reserve --script res://tests/test_hatch_reserve.gd
run_godot_check air-deadline --script res://tests/test_air_deadline.gd
run_godot_check late-shift-goals --script res://tests/test_late_shift_goals.gd
run_godot_check day4-supply-cache --script res://tests/test_day4_supply_cache.gd
run_godot_check next-flicker --script res://tests/test_next_flicker.gd
run_godot_check shed-tray-tip --script res://tests/test_shed_tray_tip.gd
run_godot_check unnamed-rec-lead --script res://tests/test_unnamed_rec_lead.gd
run_godot_check medbed-bunk-card --script res://tests/test_medbed_bunk_card.gd
run_godot_check alert-line-cap --script res://tests/test_alert_line_cap.gd
run_godot_check spend-places-build --script res://tests/test_spend_places_build.gd
run_godot_check wing-best --script res://tests/test_wing_best.gd
run_godot_check wing-best-behavior --script res://tests/test_wing_best_behavior.gd
run_godot_check death-recap --script res://tests/test_death_recap.gd
run_godot_check retry-checkpoint-match --script res://tests/test_retry_checkpoint_match.gd
run_godot_check medical --script res://tests/test_medical.gd
run_godot_check medical-next-threshold --script res://tests/test_medical_next_threshold.gd
run_godot_check survival-next --script res://tests/test_survival_next.gd
run_godot_check salvage-guidance --script res://tests/test_salvage_guidance.gd
run_godot_check fixture-props --script res://tests/test_fixture_props.gd
run_godot_check proxy-kind-on-load --script res://tests/test_proxy_kind_on_load.gd
run_godot_check open-suggested-tab --script res://tests/test_open_suggested_tab.gd
run_godot_check crew-grade --script res://tests/test_crew_grade.gd
run_godot_check stockpile-zones --script res://tests/test_stockpile_zones.gd
run_godot_check oxygen-forecast --script res://tests/test_oxygen_forecast.gd
run_godot_check food-hauling --script res://tests/test_food_hauling.gd
run_godot_check food-props --script res://tests/test_food_props.gd
run_godot_check food-loop-playthrough --script res://tests/test_food_loop_playthrough.gd
run_godot_check air-fund-tip --script res://tests/test_air_fund_tip.gd
run_godot_check air-loop-playthrough --script res://tests/test_air_loop_playthrough.gd
run_godot_check loss-screen-status --script res://tests/test_loss_screen_status.gd
run_godot_check hatch-walk-playthrough --script res://tests/test_hatch_walk_playthrough.gd
run_godot_check forced-hatch-status --script res://tests/test_forced_hatch_status.gd
run_godot_check f6-forced-responder-seam --script res://tests/test_f6_forced_responder_seam.gd
run_godot_check f6-p3-guidance --script res://tests/test_f6_p3_guidance.gd
run_godot_check continuous-food-air-walk --script res://tests/test_continuous_food_air_walk.gd
run_godot_check roster-fit --script res://tests/test_roster_fit.gd
run_godot_check post-seal-designate-pressure --script res://tests/test_post_seal_designate_pressure.gd
run_godot_check loss-screen-tool-help --script res://tests/test_loss_screen_tool_help.gd
run_godot_check fresh-wing-next-walk --script res://tests/test_fresh_wing_next_walk.gd
run_godot_check loss-clock --script res://tests/test_loss_clock.gd
run_godot_check fresh-wing-charge-finish --script res://tests/test_fresh_wing_charge_finish.gd
run_godot_check preview-tool-on-load --script res://tests/test_preview_tool_on_load.gd
run_godot_check fresh-wing-grow-finish --script res://tests/test_fresh_wing_grow_finish.gd
run_godot_check air-haze --script res://tests/test_air_haze.gd
run_godot_check fresh-wing-nutrient-finish --script res://tests/test_fresh_wing_nutrient_finish.gd
run_godot_check breach-alarm --script res://tests/test_breach_alarm.gd
run_godot_check fresh-wing-air-finish --script res://tests/test_fresh_wing_air_finish.gd
run_godot_check lit-signature --script res://tests/test_lit_signature.gd
run_godot_check lighting-darkness --script res://tests/test_lighting_darkness.gd
run_godot_check thin-air-work --script res://tests/test_thin_air_work.gd
run_godot_check manual-draft-forced-orders --script res://tests/test_manual_draft_forced_orders.gd
run_godot_check terrain-aware-picking --script res://tests/test_terrain_aware_picking.gd
run_godot_check hatch-path-cache --script res://tests/test_hatch_path_cache.gd
run_godot_check boot --quit-after 5
run_godot_check topbar-fit --script res://tests/test_topbar_fit.gd

# Fresh-clone cold boot: class cache must resolve global GDScript classes without an editor visit.
COLD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vault-tycoon-cold.XXXXXX")"
git archive HEAD | tar -x -C "$COLD_ROOT"
if [[ ! -f "$COLD_ROOT/.godot/global_script_class_cache.cfg" ]]; then
	echo "Missing committed .godot/global_script_class_cache.cfg in archive." >&2
	exit 1
fi
COLD_LOG="$TEST_DATA_DIR/cold_boot.log"
if ! XDG_DATA_HOME="$TEST_DATA_DIR/cold_userdata" timeout "$GODOT_CHECK_TIMEOUT" "$GODOT_BIN" --headless --path "$COLD_ROOT" --quit-after 2 2>&1 | tee "$COLD_LOG"; then
	echo "Cold-boot Godot launch failed." >&2
	exit 1
fi
if grep -E -q 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$COLD_LOG"; then
	echo "Cold-boot launch logged script/parse errors (HUD would be missing)." >&2
	exit 1
fi
echo "Cold-boot class-cache check passed."

# Wing seed (QA 2026-10-18c #2) runs last so no merge-plan check.sh context moves.
run_godot_check wing-seed --script res://tests/test_wing_seed.gd
run_godot_check wing-layout --script res://tests/test_wing_layout.gd
run_godot_check seed-visible --script res://tests/test_seed_visible.gd
run_godot_check pre-layout-contents --script res://tests/test_pre_layout_contents.gd
run_godot_check crew-traits --script res://tests/test_crew_traits.gd
run_godot_check crew-roster --script res://tests/test_crew_roster.gd
run_godot_check trait-text-fit --script res://tests/test_trait_text_fit.gd
run_godot_check wing-records --script res://tests/test_wing_records.gd
run_godot_check records-isolation --script res://tests/test_records_isolation.gd
run_godot_check perks --script res://tests/test_perks.gd
run_godot_check perk-row --script res://tests/test_perk_row.gd
run_godot_check perks-p3 --script res://tests/test_perks_p3.gd
run_godot_check crew-size --script res://tests/test_crew_size.gd
run_godot_check annex-b1 --script res://tests/test_annex_b1.gd
run_godot_check annex-b2 --script res://tests/test_annex_b2.gd
run_godot_check annex-b3 --script res://tests/test_annex_b3.gd
run_godot_check relay-lumen-power --script res://tests/test_relay_lumen_power.gd
run_godot_check relay-lumen-old-save --script res://tests/test_relay_lumen_old_save.gd
run_godot_check briefing-stepper-focus --script res://tests/test_briefing_stepper_focus.gd
run_godot_check records-finish --script res://tests/test_records_finish.gd
run_godot_check sublevel --script res://tests/test_sublevel.gd
run_godot_check sublevel-modifiers --script res://tests/test_sublevel_modifiers.gd
run_godot_check sublevel-stepper --script res://tests/test_sublevel_stepper.gd
run_godot_check records-keep-running --script res://tests/test_records_keep_running.gd
run_godot_check replay-wing --script res://tests/test_replay_wing.gd

echo "All Vault Tycoon headless checks passed."
