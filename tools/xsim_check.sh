#!/usr/bin/env bash
#
# xsim_check.sh - the verdict regression_test.sh gives one simulation.
#
# Usage:
#   xsim_check.sh <log> <status>
#
# <log> and <status> are what xsim_run.sh wrote. A case passes, as in
# regression_test.sh, when run_xsim.sh exited 0, the log carries one of
# the testbench's pass markers and none of its failure markers, and the
# Micron model reported no timing VIOLATION.
set -uo pipefail

log="$1" status="$2"

out_dir="${TEST_UNDECLARED_OUTPUTS_DIR:-}"
if [[ -n "$out_dir" ]]; then
    cp -f "$log" "$out_dir/sim.log"
fi

rc="$(cat "$status")"
violations="$(grep -c "VIOLATION" "$log" || true)"

if [[ "$rc" == "0" ]] \
    && grep -q "PASS: All test phases + BIST\|PASS: init_failed asserted as expected\|PASS: CSR reset test" "$log" \
    && ! grep -q "Simulation FAILED\|FAIL: rd_err\|FAIL: bist" "$log" \
    && [[ "$violations" -eq 0 ]]; then
    grep -A6 "CALIBRATION RESULTS" "$log" | grep -E "Gate:|Eye:|WL:|OK:|WARNING:" || true
    echo "PASS"
    exit 0
fi

tail -n 40 "$log"
echo "FAIL (run_xsim.sh exit $rc)"
if [[ "$violations" -gt 0 ]]; then
    echo "  Reason: $violations Micron model VIOLATION(s)"
elif grep -q "TIMEOUT:" "$log"; then
    echo "  Reason: simulation timeout"
elif grep -q "CALIB_ERROR" "$log"; then
    echo "  Reason: calibration error"
elif grep -q "FAIL:" "$log"; then
    echo "  Reason: data mismatch"
fi
exit 1
