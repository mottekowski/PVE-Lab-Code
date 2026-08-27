#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - Scheduled Verify + historische Aktivitaet scope-sicher; kein Verify-Start.
set -u
umask 077
SCRIPT_NAME="AP3-53-PBSVerify"; SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"; AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"; ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
raw="$(proxmox-backup-manager verify-job list --output-format text 2>&1)"; rc=$?
if (( rc != 0 )); then ap3_emit "$node" "Verify" "Scheduled verify jobs" "$(ap3_classify_error "$rc" "$raw")" "local proxmox-backup-manager verify-job list" "$ts"
else
  recs="$(ap3_box_table_records "$raw" 2>/dev/null || true)"; total=0; scoped=0
  if [[ -n "$recs" ]]; then while IFS="$AP3_TABLE_SEP" read -r rec first summary; do [[ -n "$summary" ]] || continue; total=$((total+1)); if ap3_record_in_scope "$summary"; then ap3_emit "$node" "Verify" "Scheduled verify job record $rec" "$summary" "local proxmox-backup-manager verify-job list; scoped filter; Unicode table normalized" "$ts"; scoped=$((scoped+1)); fi; done <<< "$recs"; fi
  if (( total == 0 )); then ap3_emit "$node" "Verify" "Scheduled verify jobs" "NONE_CONFIGURED" "local proxmox-backup-manager verify-job list" "$ts"; elif (( scoped == 0 )); then ap3_emit "$node" "Verify" "Scheduled verify jobs" "NOT_APPLICABLE: no verify job attributable to AP3 datastore/namespace scope" "local proxmox-backup-manager verify-job list; scoped filter" "$ts"; fi
fi
traw="$(proxmox-backup-manager task list --all true --limit 200 --output-format text 2>&1)"; trc=$?
if (( trc != 0 )); then ap3_emit "$node" "Verify" "Historical verify activity (last 200 tasks)" "$(ap3_classify_error "$trc" "$traw")" "local proxmox-backup-manager task list; scoped presence check" "$ts"
else
  task_records="$(ap3_scoped_task_records "$traw" 2>/dev/null)"; task_rc=$?
  if (( task_rc == 2 )); then ap3_emit "$node" "Verify" "Historical verify activity (last 200 tasks)" "NOT_APPLICABLE: namespace-specific task attribution is not unambiguous from UPID; global history not exported" "local task list; scope isolation" "$ts"
  elif [[ -n "$task_records" ]] && printf '%s\n' "$task_records" | awk -F "$AP3_TABLE_SEP" 'tolower($3)=="verify"{found=1} END{exit found?0:1}'; then ap3_emit "$node" "Verify" "Historical verify activity (last 200 tasks)" "PRESENT" "local task list; only safely scoped UPIDs inspected" "$ts"
  else ap3_emit "$node" "Verify" "Historical verify activity (last 200 tasks)" "NONE_OBSERVED" "local task list; only safely scoped UPIDs inspected" "$ts"; fi
fi
ap3_emit "$node" "Verify" "Ad-hoc verify" "NOT_EXECUTED: active verify intentionally excluded" "proxmox-backup-manager verify-job run ... (not run)" "$ts"
} > "$OUT_FILE"; printf '%s\n' "$OUT_FILE"
