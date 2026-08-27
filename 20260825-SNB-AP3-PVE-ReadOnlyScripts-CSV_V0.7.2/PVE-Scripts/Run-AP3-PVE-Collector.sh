#!/usr/bin/env bash
# AP3 V0.7.2 - PVE-seitiger Collector.
# Alle PVE-Nodes werden von einem PVE-Collector erfasst. PBS wird niemals per SSH angesprochen.
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ap3-pve.sh"
AUTO_MERGE=1
usage(){ cat <<USAGE
Usage: $0 [--no-merge]

Ausfuehrung:
  cd <Paket>/PVE-Scripts
  sudo ./Run-AP3-PVE-Collector.sh

PVE-Modell:
  - lokaler PVE-Host = Collector
  - weitere PVE-Hosts per SSH
  - kein SSH/API-Zugriff vom Collector auf PBS
  - Raw:    PVE-Out/<Run-ID>/
  - Merged: PVE-Merged/<Run-ID>/
  - Scope:  PVE-Merged/<Run-ID>/<Run-ID>_AP3_PBS_Scope.csv
USAGE
}
while [[ $# -gt 0 ]]; do case "$1" in --no-merge) AUTO_MERGE=0; shift;; -h|--help) usage; exit 0;; *) echo "Unknown option: $1" >&2; usage >&2; exit 64;; esac; done
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo 'ERROR: PVE-Collector muss mit EUID 0/root ausgefuehrt werden.' >&2; exit 1; }
command -v pvesh >/dev/null 2>&1 || { echo 'ERROR: pvesh fehlt; kein PVE-Host erkannt.' >&2; exit 1; }
[[ -d /etc/pve || -n "${AP3_PVE_STORAGE_CFG:-}" ]] || { echo 'ERROR: /etc/pve fehlt; kein PVE-Host erkannt.' >&2; exit 1; }
for c in ssh awk sed grep sha256sum date; do command -v "$c" >/dev/null 2>&1 || { echo "ERROR: Erforderlicher Befehl fehlt: $c" >&2; exit 1; }; done
export AP3_COLLECTOR_NODE="${AP3_COLLECTOR_NODE:-$(hostname -s 2>/dev/null || hostname)}"
export AP3_RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"
export AP3_OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PVE-Out}"
export AP3_MERGED_ROOT="${AP3_MERGED_ROOT:-${SCRIPT_DIR}/PVE-Merged}"
export AP3_PVE_HOSTS_FILE="${AP3_PVE_HOSTS_FILE:-${SCRIPT_DIR}/pve-hosts.txt}"
mkdir -p "${AP3_OUTPUT_ROOT}/${AP3_RUN_ID}" "${AP3_MERGED_ROOT}/${AP3_RUN_ID}" "${SCRIPT_DIR}/runlogs"
PRECHECK="${SCRIPT_DIR}/runlogs/${AP3_RUN_ID}_PVE_Precheck.log"
ap3_load_pve_hosts PVE_HOSTS
{
 echo '======================================================================'
 echo ' AP3 V0.7.2 - PVE COLLECTOR PRECHECK'
 echo '======================================================================'
 printf 'Run-ID          : %s\n' "$AP3_RUN_ID"
 printf 'Collector       : %s\n' "$AP3_COLLECTOR_NODE"
 printf 'Execution user  : %s (uid=%s)\n' "$(id -un)" "$(id -u)"
 printf 'PVE Raw         : %s/%s\n' "$AP3_OUTPUT_ROOT" "$AP3_RUN_ID"
 printf 'PVE Merged      : %s/%s\n' "$AP3_MERGED_ROOT" "$AP3_RUN_ID"
 printf 'PBS SSH         : NOT_USED\n'
 echo 'PVE targets:'
 for h in "${PVE_HOSTS[@]}"; do
   mode="$(ap3_pve_mode "$h")"; result="$(ap3_pve_capture "$h" "printf 'hostname='; hostname -s; printf ' uid='; id -u; printf ' pvesh='; command -v pvesh || true" || true)"
   printf '  %-24s %-6s %s\n' "$h" "$mode" "$result"
 done
} | tee "$PRECHECK"
for s in AP3-31-PBSNet.sh AP3-32-PBSTLS.sh AP3-33-PBSRepo.sh AP3-51-PVEJobs.sh; do
  if ! "${SCRIPT_DIR}/$s"; then printf 'WARN: %s wurde mit Fehler beendet.\n' "$s" >&2; fi
done
if ! "${SCRIPT_DIR}/Build-AP3-PBS-Scope.sh"; then printf 'WARN: PBS Scope-Handoff konnte nicht erzeugt werden.\n' >&2; fi
if [[ "$AUTO_MERGE" -eq 1 ]]; then
  "${SCRIPT_DIR}/Merge-AP3-PVE.sh" "$AP3_RUN_ID" || printf 'WARN: PVE-Merge mit Fehler beendet.\n' >&2
  "${SCRIPT_DIR}/Build-AP3-PVE-EvidenceIndex.sh" "$AP3_RUN_ID" || printf 'WARN: PVE Evidence_Index mit Fehler beendet.\n' >&2
fi
printf 'AP3 V0.7.2 PVE-Erhebung abgeschlossen. Run-ID: %s\n' "$AP3_RUN_ID"
