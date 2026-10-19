#!/usr/bin/env bash
#
# Measure the time from `open` to the first window being on screen, split into
# the part LaunchServices owns (open → exec) and the part Segue owns (exec →
# window drawn). Runs N launches (default 5; the first warms the caches) and
# prints each number plus the medians. The budget is 200 ms for Segue's part
# (CLAUDE.md); LaunchServices adds roughly 100 ms on top that we can't change.
#
#   scripts/cold-start.sh [--app build/Segue.app] [--runs 5]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Segue.app"
RUNS=5
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) APP="$2"; shift 2 ;;
        --runs) RUNS="$2"; shift 2 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done
[[ -d "$APP" ]] || { echo "error: $APP not found; run make bundle first" >&2; exit 1; }
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"   # open(1) needs an absolute path

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

totals=()
ours=()
for ((i = 1; i <= RUNS; i++)); do
    marker="$(mktemp -t segue-startup)"
    rm -f "$marker"
    start="$(now_ms)"
    open -n "$APP" --args --startup-marker "$marker"
    for ((t = 0; t < 500; t++)); do
        [[ -s "$marker" ]] && break
        sleep 0.01
    done
    if [[ ! -s "$marker" ]]; then
        echo "run $i: timed out (no marker written)" >&2
        continue
    fi
    read -r ready exec_at < "$marker"
    rm -f "$marker"
    total=$((ready - start))
    mine=$((ready - exec_at))
    totals+=("$total")
    ours+=("$mine")
    printf 'run %d: %4d ms open→window   = %3d ms LaunchServices + %3d ms Segue\n' "$i" "$total" "$((exec_at - start))" "$mine"
    sleep 0.3
done

median() { printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
if [[ ${#ours[@]} -gt 0 ]]; then
    m_total="$(median "${totals[@]}")"
    m_ours="$(median "${ours[@]}")"
    echo "median: ${m_total} ms open→window, ${m_ours} ms Segue's part (budget 200 ms)"
    [[ "$m_ours" -le 200 ]] || { echo "OVER BUDGET" >&2; exit 1; }
fi
