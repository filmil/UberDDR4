#!/usr/bin/env bash
#
# eda_test.sh - one check from run_compile.sh, as a Bazel test.
#
# Usage:
#   eda_test.sh lint     <verilator> <top> <file>...
#   eda_test.sh iverilog <iverilog> <file>...
#   eda_test.sh yosys    <yosys> <top> <file>...
#   eda_test.sh sby      <sby> <sby-file> <task>
#   eda_test.sh ascii    <file>...
#
# Each mode runs the same command, with the same flags, as the matching
# stage of run_compile.sh, and passes or fails the same way. Tool logs go
# to the test's undeclared outputs (bazel-testlogs/<target>/test.outputs/),
# which is where run_compile.sh's build_logs/ went.
#
# Bazel starts a test in the root of its runfiles, the same place as the
# repository root, so the relative paths that run_compile.sh uses work
# here unchanged.
set -euo pipefail

mode="${1:?usage: eda_test.sh <mode> ...}"
shift

out_dir="${TEST_UNDECLARED_OUTPUTS_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$out_dir"
log="$out_dir/${mode}.log"

# Runs a tool with its output in the log, then shows the log, so that it
# is in the test log too.
run_logged() {
    local rc=0
    "$@" > "$log" 2>&1 || rc=$?
    cat "$log"
    return "$rc"
}

case "$mode" in
    lint)
        verilator="$1" top="$2"
        shift 2
        run_logged "$verilator" --lint-only -Wall --top-module "$top" "$@"
        ;;
    iverilog)
        iverilog="$1"
        shift
        run_logged "$iverilog" -g2012 -Wall -t null "$@"
        ;;
    yosys)
        yosys="$1" top="$2"
        shift 2
        script="read_verilog -sv $*; hierarchy -top $top -check -purge_lib; proc; opt; check"
        run_logged "$yosys" -q -p "$script"
        ;;
    sby)
        sby="$1" sby_file="$2" task="$3"
        # SymbiYosys writes its work directory beside the .sby file unless
        # told otherwise, and the runfiles tree is not writable.
        work="${TEST_TMPDIR:?}/sby_${task}"
        rc=0
        run_logged "$sby" -f -d "$work" "$sby_file" "$task" || rc=$?
        cp -f "$work/logfile.txt" "$out_dir/sby_${task}_logfile.txt" 2>/dev/null || true
        # run_compile.sh counts a task as passed when it leaves a PASS file.
        if (( rc != 0 )) || [[ ! -e "$work/PASS" ]]; then
            echo "FAIL: $task (sby exit $rc)" >&2
            exit 1
        fi
        echo "PASS: $task"
        ;;
    ascii)
        # Tabs and printable ASCII only; -I skips binary files.
        offenders="$(LC_ALL=C grep -lI $'[^\t -~]' "$@" || true)"
        if [[ -n "$offenders" ]]; then
            echo "FAIL: non-ASCII bytes in:" >&2
            for f in $offenders; do
                echo "  $f" >&2
                LC_ALL=C grep -n $'[^\t -~]' "$f" | head -3 | sed 's/^/    /' >&2
            done
            exit 1
        fi
        echo "PASS: $# files are ASCII-only"
        ;;
    *)
        echo "eda_test.sh: unknown mode: $mode" >&2
        exit 2
        ;;
esac
