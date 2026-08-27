#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - Prune Jobs nur fuer den scoped Datastore/Namespace.
set -u
umask 077
SCRIPT_NAME="AP3-52-PBSPrune"; SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"; AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"; ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
raw="$(proxmox-backup-manager prune-job list --output-format text 2>&1)"; rc=$?
if (( rc != 0 )); then ap3_emit "$node" "Retention" "Prune job inventory" "$(ap3_classify_error "$rc" "$raw")" "local proxmox-backup-manager prune-job list" "$ts"
else
  recs="$(ap3_box_table_records "$raw" 2>/dev/null || true)"; total=0; scoped=0
  if [[ -n "$recs" ]]; then
    while IFS="$AP3_TABLE_SEP" read -r rec first summary; do
      [[ -n "$summary" ]] || continue; total=$((total+1))
      if ap3_record_in_scope "$summary"; then ap3_emit "$node" "Retention" "Prune job record $rec" "$summary" "local proxmox-backup-manager prune-job list; scoped filter; Unicode table normalized" "$ts"; scoped=$((scoped+1)); fi
    done <<< "$recs"
  fi
  if (( total == 0 )); then ap3_emit "$node" "Retention" "Prune job inventory" "NONE_CONFIGURED" "local proxmox-backup-manager prune-job list" "$ts"
  elif (( scoped == 0 )); then ap3_emit "$node" "Retention" "Prune job inventory" "NOT_APPLICABLE: no prune job attributable to AP3 datastore/namespace scope" "local proxmox-backup-manager prune-job list; scoped filter" "$ts"; fi
fi
} > "$OUT_FILE"; printf '%s\n' "$OUT_FILE"
