#!/usr/bin/env bash
# AP3 V0.7.2 / PVE - clusterweite PVE Backup-Jobs und PVE-seitige prune-backups-Konfiguration.
set -u
umask 077
SCRIPT_NAME="AP3-51-PVEJobs"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ap3-pve.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PVE-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"
PVE_JOBS_CFG="${AP3_PVE_JOBS_CFG:-/etc/pve/jobs.cfg}"; PVE_STORAGE_CFG="${AP3_PVE_STORAGE_CFG:-/etc/pve/storage.cfg}"
mkdir -p "$OUT_DIR"
{
printf '%s\n' "$AP3_DATA_HEADER"
ts="$(ap3_iso_ts)"; node="$AP3_COLLECTOR_NODE"
ap3_emit "$node" "Collector" "Execution mode" "LOCAL; collector=${AP3_COLLECTOR_NODE}; clusterwide pmxcfs data; environment=PVE" "local /etc/pve on collector" "$ts"
cmd="awk 'function flush(){if(id!=\"\"){print id\"|schedule|\"schedule;if(storage!=\"\")print id\"|storage|\"storage;if(mode!=\"\")print id\"|mode|\"mode;if(enabled!=\"\")print id\"|enabled|\"enabled;if(allv!=\"\")print id\"|all|\"allv;if(vmid!=\"\")print id\"|vmid|\"vmid;if(exclude!=\"\")print id\"|exclude|\"exclude;if(nodev!=\"\")print id\"|node|\"nodev;if(bw!=\"\")print id\"|bwlimit|\"bw}id=schedule=storage=mode=enabled=allv=vmid=exclude=nodev=bw=\"\"} /^[[:space:]]*vzdump:[[:space:]]+/{if(inx)flush();id=\$2;inx=1;next} inx&&/^[^[:space:]]/{flush();inx=0} inx{key=\$1;\$1=\"\";sub(/^[[:space:]]+/,\"\",\$0);v=\$0;if(key==\"schedule\")schedule=v;else if(key==\"storage\")storage=v;else if(key==\"mode\")mode=v;else if(key==\"enabled\")enabled=v;else if(key==\"all\")allv=v;else if(key==\"vmid\")vmid=v;else if(key==\"exclude\")exclude=v;else if(key==\"node\")nodev=v;else if(key==\"bwlimit\")bw=v} END{if(inx)flush()}' '$PVE_JOBS_CFG' 2>/dev/null"
jobs="$(ap3_local_capture "$cmd" || true)"
if [[ "$jobs" == ERROR\(* ]]; then ap3_emit "$node" "Job" "PVE backup jobs" "$jobs" "$PVE_JOBS_CFG whitelist (local on collector PVE)" "$ts"
elif [[ -z "$jobs" ]]; then ap3_emit "$node" "Job" "PVE backup jobs" "NOT_CONFIGURED" "$PVE_JOBS_CFG whitelist (local on collector PVE)" "$ts"
else while IFS='|' read -r id key val; do [[ -n "$id" ]] || continue; ap3_emit "PVE cluster / job $id" "Job" "$key" "$val" "$PVE_JOBS_CFG clusterwide whitelist (local on collector PVE)" "$ts"; done <<< "$jobs"; fi
retention="$(ap3_local_capture "awk 'function flush(){if(id!=\"\")print id\"|prune-backups|\"(pr!=\"\"?pr:\"NONE_CONFIGURED\");id=pr=\"\"} /^[[:space:]]*pbs:[[:space:]]+/{if(inx)flush();id=\$2;inx=1;next} inx&&/^[^[:space:]]/{flush();inx=0} inx{key=\$1;\$1=\"\";sub(/^[[:space:]]+/,\"\",\$0);if(key==\"prune-backups\")pr=\$0} END{if(inx)flush()}' '$PVE_STORAGE_CFG' 2>/dev/null" || true)"
if [[ "$retention" == ERROR\(* ]]; then ap3_emit "$node" "Retention" "PVE PBS retention" "$retention" "$PVE_STORAGE_CFG whitelist (local on collector PVE)" "$ts"
elif [[ -z "$retention" ]]; then ap3_emit "$node" "Retention" "PVE PBS storage prune-backups" "NOT_CONFIGURED: no PBS storage block found" "$PVE_STORAGE_CFG whitelist (local on collector PVE)" "$ts"
else while IFS='|' read -r id key val; do [[ -n "$id" ]] || continue; ap3_emit "PVE storage $id" "Retention" "$key" "$val" "$PVE_STORAGE_CFG clusterwide whitelist (local on collector PVE)" "$ts"; done <<< "$retention"; fi
} > "$OUT_FILE"
printf '%s\n' "$OUT_FILE"
