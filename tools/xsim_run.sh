#!/usr/bin/env bash
#
# xsim_run.sh - one regression_test.sh case, as a Bazel build action.
#
# Usage:
#   xsim_run.sh <vivado> <log> <status> <timeout-minutes> <phy-impl> \
#               <env.sh> <dst>=<src>...
#
# Lays the inputs out in a fresh directory as a checkout would have them,
# testbench/micron/ included, then runs testbench/run_xsim.sh there with
# the environment regression_test.sh gives that case. This keeps the
# simulation the repository's own script, unchanged.
#
#   <vivado>   the Vivado installation, which run_xsim.sh calls XILINX_VIVADO
#   <log>      where the simulation log goes
#   <status>   where the exit status of run_xsim.sh goes
#   <env.sh>   MICRON_DENSITY and MICRON_SPEED, from regression_row.sh
#   <dst>=<src>  an input <src>, placed at <dst> in the checkout layout
#
# The action itself succeeds whenever the simulation ran, pass or fail; the
# test that reads <log> and <status> decides. A cached failing run is then
# reported as a failing test, rather than rerun as a failing build.
set -euo pipefail

vivado="$1" log="$2" status="$3" timeout_minutes="$4" phy_impl="$5" env_file="$6"
shift 6

log="$PWD/$log"
status="$PWD/$status"
stage="$(mktemp -d "${TMPDIR:-/tmp}/uberddr4_xsim.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

for pair in "$@"; do
    dst="${pair%%=*}" src="${pair#*=}"
    mkdir -p "$stage/$(dirname "$dst")"
    cp -L "$src" "$stage/$dst"
done

# shellcheck source=/dev/null
source "$env_file"

export XILINX_VIVADO="$vivado"
export MICRON_DENSITY MICRON_SPEED
export PHY_IMPL="$phy_impl"
export SIM_CONFIG_FILE="testbench/regression_logs/regression_config.vh"
# regression_test.sh keeps waveform dumping off in a regression.
export DUMP_VCD=0
# And it quiets the native PHY's per-tap training log.
if [[ "$phy_impl" == "native" ]]; then
    export EXTRA_DEFINES="-d SIM_QUIET_TRAINING_LOG"
else
    export EXTRA_DEFINES=""
fi

cd "$stage"
rc=0
timeout --signal=TERM --kill-after=10s "${timeout_minutes}m" \
    bash testbench/run_xsim.sh > "$log" 2>&1 || rc=$?
# regression_test.sh marks a case that ran out of wall time this way.
if [[ $rc -eq 124 ]] && ! grep -q "TIMEOUT:" "$log"; then
    printf 'TIMEOUT: simulation exceeded %s minutes\n' "$timeout_minutes" >> "$log"
fi
echo "$rc" > "$status"
