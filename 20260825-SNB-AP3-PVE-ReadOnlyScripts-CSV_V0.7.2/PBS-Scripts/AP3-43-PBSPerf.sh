#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - non-invasive Performance-Indikatoren fuer scoped Datastores plus klar markierter Host-Kontext.
set -u
umask 077
SCRIPT_NAME="AP3-43-PBSPerf"; SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"; AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"; ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
for ds in "${AP3_SCOPE_DATASTORES[@]}"; do
  scope="$node / datastore $ds"; path="$(ap3_datastore_path "$ds")"; [[ -n "$path" ]] || { ap3_emit "$scope" "Performance" "IO latency / utilization sample" "COLLECTION_FAILED(rc=2): datastore path not found" "$AP3_PBS_DATASTORE_CFG" "$ts"; continue; }
  src="$(findmnt -no SOURCE -T "$path" 2>/dev/null | head -n1)"
  if command -v iostat >/dev/null 2>&1 && [[ "$src" == /dev/* ]]; then
    dev="$(basename "$src")"; v="$(iostat -xz 1 5 "$dev" 2>&1)"; rc=$?; (( rc==0 )) && ap3_emit "$scope" "Performance" "IO latency / utilization sample" "$v" "iostat -xz 1 5 <scoped block device>" "$ts" || ap3_emit "$scope" "Performance" "IO latency / utilization sample" "$(ap3_classify_error "$rc" "$v")" "iostat -xz 1 5 <scoped block device>" "$ts"
  elif ! command -v iostat >/dev/null 2>&1; then ap3_emit "$scope" "Performance" "IO latency / utilization sample" "NOT_SUPPORTED: iostat not installed" "iostat" "$ts"
  else ap3_emit "$scope" "Performance" "IO latency / utilization sample" "NOT_APPLICABLE: no direct block device attributable to datastore" "findmnt SOURCE" "$ts"; fi
done
v="$(uptime; free -h 2>/dev/null || true; printf '\nTOP CPU PROCESSES (no user column):\n'; ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n15)"
ap3_emit "$node" "Performance" "CPU / Memory snapshot" "$v" "HOST-WIDE CONTEXT on central PBS; uptime; free -h; ps without user column" "$ts"
} > "$OUT_FILE"; printf '%s\n' "$OUT_FILE"
