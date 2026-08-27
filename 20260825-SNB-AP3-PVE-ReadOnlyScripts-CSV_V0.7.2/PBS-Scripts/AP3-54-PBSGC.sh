#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - Garbage Collection Status nur fuer scoped Datastores; kein GC-Start.
set -u
umask 077
SCRIPT_NAME="AP3-54-PBSGC"; SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"; AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"; ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
for ds in "${AP3_SCOPE_DATASTORES[@]}"; do
  scope="$node / datastore $ds"
  st="$(proxmox-backup-manager garbage-collection status "$ds" --output-format text 2>&1)"; rc=$?
  if (( rc != 0 )); then ap3_emit "$scope" "GC" "Garbage collection status" "$(ap3_classify_error "$rc" "$st")" "local proxmox-backup-manager garbage-collection status <scoped store>" "$ts"; continue; fi
  kv="$(ap3_box_table_key_values "$st" 2>/dev/null || true)"
  if [[ -n "$kv" ]]; then while IFS="$AP3_TABLE_SEP" read -r key value; do [[ -n "$key" ]] && ap3_emit "$scope" "GC" "$key" "${value:-NONE_CONFIGURED}" "local garbage-collection status; Name/Value table normalized" "$ts"; done <<< "$kv"
  else ap3_emit "$scope" "GC" "Garbage collection status" "${st:-NONE_CONFIGURED}" "local proxmox-backup-manager garbage-collection status <scoped store>" "$ts"; fi
done
ap3_emit "$node" "GC" "Active garbage collection" "NOT_EXECUTED: GC start intentionally excluded" "proxmox-backup-manager garbage-collection start ... (not run)" "$ts"
} > "$OUT_FILE"; printf '%s\n' "$OUT_FILE"
