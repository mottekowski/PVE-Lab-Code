#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - lokaler PBS Systemstatus. Kein SSH zu PVE.
set -u
umask 077
SCRIPT_NAME="AP3-20-PBSSystem"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"
AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"
ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
v="$(ap3_pbs_capture "if command -v proxmox-backup-manager >/dev/null 2>&1; then proxmox-backup-manager versions --output-format text 2>/dev/null || proxmox-backup-manager versions; else echo 'COMMAND_NOT_SUPPORTED'; fi" || true)"; ap3_emit "$node" "System" "PBS versions" "$v" "local proxmox-backup-manager versions" "$ts"
os="$(ap3_pbs_capture "printf 'kernel='; uname -r; if [ -r /etc/os-release ]; then . /etc/os-release; printf ' os=%s %s\\n' \"\${NAME:-unknown}\" \"\${VERSION_ID:-unknown}\"; fi" || true)"; ap3_emit "$node" "System" "OS / Kernel" "$os" "local uname -r; /etc/os-release" "$ts"
svc="$(ap3_pbs_capture "for s in proxmox-backup proxmox-backup-proxy; do printf '%s=' \"\$s\"; systemctl is-active \"\$s.service\" 2>/dev/null || true; printf ' '; done" || true)"; ap3_emit "$node" "Health" "PBS service state" "$svc" "local systemctl is-active" "$ts"
errc="$(ap3_pbs_capture "journalctl -u proxmox-backup -u proxmox-backup-proxy --since '-24 hours' -p warning --no-pager 2>/dev/null | grep -v '^--' | wc -l" || true)"; ap3_emit "$node" "Health" "Warning/Error log lines last 24h" "$errc" "local journalctl count only; content not exported" "$ts"
ports="$(ap3_pbs_capture "ss -lntp 2>/dev/null | awk 'NR==1 || \$4 ~ /:8007$|:22$/'" || true)"; ap3_emit "$node" "Connectivity" "Listening TCP ports 8007/22" "$ports" "local ss -lntp; no PVE/PBS SSH dependency" "$ts"
ap3_emit "$node" "Collector" "Cross-environment SSH" "NOT_APPLICABLE: PVE<->PBS SSH/TCP22 is not used by AP3 V0.7.2" "collector architecture" "$ts"
ap3_emit "$node" "Connectivity" "Reverse PBS -> PVE probe" "NOT_EXECUTED: cross-environment probes from PBS are outside the separated V0.7.2 collector design" "collector architecture; former AP3-31-PBSBack retired" "$ts"
} > "$OUT_FILE"
printf '%s\n' "$OUT_FILE"
