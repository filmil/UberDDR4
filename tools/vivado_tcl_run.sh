#!/usr/bin/env bash
#
# vivado_tcl_run.sh - run a repository Tcl script in Vivado batch mode, as a
# Bazel build action.
#
# Usage:
#   vivado_tcl_run.sh <vivado> <log> <dir> <script> <tclargs> \
#                     <dst>=<src>... -- <out>=<dest>...
#
#   <vivado>   the Vivado installation
#   <log>      where Vivado's log goes
#   <dir>      the directory to start Vivado in, relative to the root
#   <script>   the Tcl script, relative to <dir>
#   <tclargs>  one word: the arguments after -tclargs, space-separated,
#              or empty for none
#   <dst>=<src>   an input, placed at <dst> in the checkout layout
#   <out>=<dest>  a file the script writes, relative to <dir>, copied to
#                 the declared output <dest>
#
# The inputs are laid out in a fresh directory as a checkout has them, and
# Vivado is started in <dir> the way that directory's Makefile starts it,
# so the script's relative paths resolve as they do there.
set -euo pipefail

vivado="$1" log="$2" dir="$3" script="$4" tclargs="$5"
shift 5

root="$PWD"
stage="$(mktemp -d "${TMPDIR:-/tmp}/uberddr4_vivado.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

while [[ $# -gt 0 && "$1" != "--" ]]; do
    dst="${1%%=*}" src="${1#*=}"
    mkdir -p "$stage/$(dirname "$dst")"
    cp -L "$src" "$stage/$dst"
    shift
done
shift

args=(-mode batch -nojournal -notrace -source "$script" -log "$root/$log")
if [[ -n "$tclargs" ]]; then
    # shellcheck disable=SC2206
    args+=(-tclargs $tclargs)
fi

cd "$stage/$dir"
"$vivado/bin/vivado" "${args[@]}"

for pair in "$@"; do
    out="${pair%%=*}" dest="${pair#*=}"
    cp -L "$out" "$root/$dest"
done
