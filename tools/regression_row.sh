#!/usr/bin/env bash
#
# regression_row.sh - the configuration of one simulation test, read from
# testbench/regression_test.sh.
#
# Usage:
#   regression_row.sh <regression_test.sh> <test> <config.vh> <env.sh>
#
# Finds <test> in the ALL_TESTS table of regression_test.sh and writes the
# two things that script derives from its row before it simulates:
#
#   <config.vh>  the `define header it calls regression_config.vh, line for
#                line as its write_regression_config writes it;
#   <env.sh>     the MICRON_DENSITY and MICRON_SPEED it exports.
#
# Reading the table rather than copying it keeps regression_test.sh the one
# place where the matrix is defined.
set -euo pipefail

script="$1" test="$2" config="$3" env="$4"

row="$(sed -n '/^ALL_TESTS=(/,/^)/p' "$script" \
    | sed -n 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
    | awk -v t="$test" '$1 == t')"
if [[ -z "$row" ]]; then
    echo "regression_row.sh: no test '$test' in $script" >&2
    exit 1
fi

read -r NAME DDR4_CLK DW LANES FLYBY MAP BIST DM DENS ROWS MICRON_DEF MICRON_SPD SPECIAL <<< "$row"

{
    printf '`define SIM_DDR4_CLK_PERIOD %s\n' "$DDR4_CLK"
    printf '`define SIM_DEVICE_WIDTH %s\n' "$DW"
    printf '`define SIM_BYTE_LANES %s\n' "$LANES"
    printf '`define SIM_FLY_BY_DELAY %s\n' "$FLYBY"
    printf '`define SIM_ADDR_MAPPING %s\n' "$MAP"
    printf '`define SIM_BIST_MODE %s\n' "$BIST"
    printf '`define SIM_BIST_DM_TEST %s\n' "$DM"
    printf '`define SIM_ROW_BITS %s\n' "$ROWS"
    if [[ "$DENS" == "4" ]]; then printf '`define SIM_DENSITY_4G\n'; fi
    if [[ "$SPECIAL" == "TRAIN_FAIL" ]]; then printf '`define SIM_FORCE_TRAIN_FAIL\n'; fi
    if [[ "$SPECIAL" == "CSR_RESET" ]]; then printf '`define SIM_CSR_RESET_TEST\n'; fi
} > "$config"

{
    printf 'MICRON_DENSITY=%s\n' "$MICRON_DEF"
    printf 'MICRON_SPEED=%s\n' "$MICRON_SPD"
} > "$env"
