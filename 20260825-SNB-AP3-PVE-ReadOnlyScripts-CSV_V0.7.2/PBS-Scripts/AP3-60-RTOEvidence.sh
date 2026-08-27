#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - RTO/RPO Read-only Evidence. Keine Restore-/Throughput-Tests.
# Task History wird nur bei sicherer Datastore-Zuordnung exportiert; Namespace-Ambiguitaet fuehrt zu keiner globalen Ausgabe.
set -u
umask 077
SCRIPT_NAME="AP3-60-RTOEvidence"; SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"; AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"; ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
raw="$(proxmox-backup-manager task list --all true --limit 200 --output-format text 2>&1)"; rc=$?
if (( rc != 0 )); then
  ap3_emit "$node" "Restore-Evidence" "Recent PBS task history" "$(ap3_classify_error "$rc" "$raw")" "local proxmox-backup-manager task list; scoped export" "$ts"
else
  records="$(ap3_scoped_task_records "$raw" 2>/dev/null)"; rrc=$?
  if (( rrc == 2 )); then
    ap3_emit "$node" "Restore-Evidence" "Recent PBS task history" "NOT_APPLICABLE: namespace-specific task attribution is not unambiguous from UPID; global task history not exported" "local task list; scope isolation" "$ts"
  elif [[ -z "$records" ]]; then
    ap3_emit "$node" "Restore-Evidence" "Recent PBS task history" "NONE_OBSERVED" "local task list; no safely attributable task in last 200" "$ts"
  else
    i=0
    while IFS="$AP3_TABLE_SEP" read -r start end type target status; do
      [[ -n "$type" ]] || continue; i=$((i+1))
      value="Start=${start:-UNKNOWN}; End=${end:-UNKNOWN}; Type=$type"; [[ -n "$target" ]] && value+="; Target=$target"; value+="; Status=${status:-UNKNOWN}"
      ap3_emit "$node / scoped task $(printf '%03d' "$i")" "Restore-Evidence" "PBS task: $type" "$value" "local task list; UPID reduced to type/target; auth IDs excluded; datastore scope filter" "$ts"
    done <<< "$records"
  fi
fi
ap3_emit "$node" "Restore-Test" "Active restore" "NOT_EXECUTED: Restore ist gemaess Read-only-Scope ausgeschlossen" "proxmox-backup-client restore ... (not run)" "$ts"
ap3_emit "$node" "Performance" "Active throughput test" "NOT_EXECUTED: iPerf ist gemaess Read-only-Scope ausgeschlossen" "iperf3 ... (not run)" "$ts"
} > "$OUT_FILE"; printf '%s\n' "$OUT_FILE"
