#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${1:-${GODOT_BIN:-/tmp/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64}}"
TEST_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vault-tycoon-headless.XXXXXX")"

cleanup() {
	rm -rf -- "$TEST_DATA_DIR"
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
	if ! XDG_DATA_HOME="$TEST_DATA_DIR" timeout 60s "$GODOT_BIN" --headless --path "$PROJECT_ROOT" "$@" 2>&1 | tee "$log_file"; then
		echo "Godot ${label} check failed." >&2
		return 1
	fi
	if grep -E -q 'SCRIPT ERROR:|Parse Error:|Failed to load script|Invalid call\.' "$log_file"; then
		echo "Godot ${label} check logged a script/runtime error." >&2
		return 1
	fi
}

run_godot_check import --editor --quit
run_godot_check tests --script res://tests/test_runner.gd
run_godot_check mood-recreation --script res://tests/test_mood_recreation.gd
run_godot_check work-priorities --script res://tests/test_work_priorities.gd
run_godot_check breach-modal-speed-keys --script res://tests/test_breach_modal_speed_keys.gd
run_godot_check medical --script res://tests/test_medical.gd
run_godot_check stockpile-zones --script res://tests/test_stockpile_zones.gd
run_godot_check food-hauling --script res://tests/test_food_hauling.gd
run_godot_check lighting-darkness --script res://tests/test_lighting_darkness.gd
run_godot_check manual-draft-forced-orders --script res://tests/test_manual_draft_forced_orders.gd
run_godot_check boot --quit-after 5

echo "All Vault Tycoon headless checks passed."
