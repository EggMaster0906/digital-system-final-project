#!/usr/bin/env sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(dirname -- "$script_dir")
output_dir=${TMPDIR:-/tmp}

sources="
$project_root/digital_system_final_project.v
$project_root/clock_divider.v
$project_root/button_conditioner.v
$project_root/traffic_controller.v
$project_root/countdown_display.v
$project_root/seven_seg_decoder.v
$project_root/lcd_controller.v
"

for test_name in traffic_controller night_mode fault_mode countdown_display lcd_controller; do
    output="$output_dir/${test_name}_tb.vvp"
    trap 'rm -f "$output"' EXIT HUP INT TERM
    echo "=== Test ${test_name}_tb ==="
    # Word splitting is intentional: source paths in this repository do not
    # contain whitespace, and Icarus Verilog requires separate path arguments.
    # shellcheck disable=SC2086
    iverilog -g2012 -Wall -s "${test_name}_tb" -o "$output" $sources \
        "$script_dir/${test_name}_tb.v"
    simulation_output=$(vvp "$output")
    printf '%s\n' "$simulation_output"
    printf '%s\n' "$simulation_output" | grep '^PASS:' >/dev/null
    if printf '%s\n' "$simulation_output" | grep '^FAIL:' >/dev/null; then
        echo "Simulation reported a failure." >&2
        exit 1
    fi
    rm -f "$output"
    trap - EXIT HUP INT TERM
done

echo "All tests passed."
