#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - lokaler Zertifikatsstatus.
set -u
umask 077
SCRIPT_NAME="AP3-32-PBSCert"; SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"; AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"; ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
out="$(ap3_pbs_capture "if command -v proxmox-backup-manager >/dev/null 2>&1; then proxmox-backup-manager cert info 2>&1; else echo 'COMMAND_NOT_SUPPORTED'; fi" || true)"
if [[ "$out" =~ ^ERROR\(rc=([0-9]+)\):[[:space:]]*(.*)$ ]]; then
  val="$(ap3_classify_error "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")"
else
  val="$out"
fi
ap3_emit "$node" "TLS" "PBS certificate info" "$val" "local proxmox-backup-manager cert info" "$ts"
} > "$OUT_FILE"; printf '%s\n' "$OUT_FILE"
