#!/usr/bin/env bash
# AP3 V0.7.2 - lokaler PBS Collector.
# Das Paket wird direkt auf PBS ausgefuehrt. Keine SSH/API-Verbindung zu PVE.
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUTO_MERGE=1
usage(){ cat <<USAGE
Usage: $0 [--no-merge]

Ausfuehrung:
  cd <Paket>/PBS-Scripts
  ./Run-AP3-PBS-Collector.sh

Berechtigung:
  - Vollstaendige Erhebung standardisiert auf EUID 0.
  - Direkter Root-Login ist nicht erforderlich.
  - Wird das Script als non-root gestartet und 'sudo -n true' funktioniert,
    re-exekutiert es sich einmalig ueber sudo -n.
  - Ohne root/sudo-n wird abgebrochen; kein interaktiver Passwortprompt.

Scope:
  Input/AP3_PBS_Scope.csv muss vorher manuell aus der PVE-Erhebung bereitgestellt werden.
USAGE
}
while [[ $# -gt 0 ]]; do case "$1" in --no-merge) AUTO_MERGE=0; shift;; -h|--help) usage; exit 0;; *) echo "Unknown option: $1" >&2; usage >&2; exit 64;; esac; done

# Vollstaendige lokale PBS-Erhebung: EUID 0. Kein Root-SSH notwendig; optional sudo-n Re-Exec.
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    printf 'INFO: non-root gestartet; versuche einmaligen Re-Exec ueber sudo -n fuer vollstaendige Read-only-Erhebung.\n' >&2
    if [[ "$AUTO_MERGE" -eq 0 ]]; then
      sudo -n -- "$0" --no-merge && exit 0
    else
      sudo -n -- "$0" && exit 0
    fi
  fi
  printf 'ERROR: Vollstaendige PBS-Erhebung benoetigt EUID 0. Bitte als root oder via fuer genau diesen Collector freigegebenes sudo -n starten. Kein interaktives sudo wird verwendet.\n' >&2
  exit 77
fi

command -v proxmox-backup-manager >/dev/null 2>&1 || { echo 'ERROR: proxmox-backup-manager fehlt; kein PBS erkannt.' >&2; exit 1; }
for c in awk sed grep sha256sum date findmnt df; do command -v "$c" >/dev/null 2>&1 || { echo "ERROR: Erforderlicher Befehl fehlt: $c" >&2; exit 1; }; done

export AP3_RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"
export AP3_OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"
export AP3_MERGED_ROOT="${AP3_MERGED_ROOT:-${SCRIPT_DIR}/PBS-Merged}"
export AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "${AP3_OUTPUT_ROOT}/${AP3_RUN_ID}" "${AP3_MERGED_ROOT}/${AP3_RUN_ID}" "${SCRIPT_DIR}/runlogs"
PRECHECK="${SCRIPT_DIR}/runlogs/${AP3_RUN_ID}_PBS_Precheck.log"
source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
 echo '======================================================================'
 echo ' AP3 V0.7.2 - LOCAL PBS COLLECTOR PRECHECK'
 echo '======================================================================'
 printf 'Run-ID          : %s\n' "$AP3_RUN_ID"
 printf 'PBS Host        : %s\n' "$(hostname -s 2>/dev/null || hostname)"
 printf 'Execution user  : %s (uid=%s)\n' "$(id -un)" "$(id -u)"
 printf 'root            : YES\n'
 printf 'sudo-n          : NOT_REQUIRED_AFTER_ELEVATION\n'
 printf 'PVE SSH/API     : NOT_USED\n'
 printf 'Scope file      : %s\n' "$AP3_PBS_SCOPE_FILE"
 printf 'Scoped datastores: %s\n' "${AP3_SCOPE_DATASTORES[*]}"
 for ds in "${AP3_SCOPE_DATASTORES[@]}"; do printf '  - %s | namespaces=%s\n' "$ds" "${AP3_SCOPE_NAMESPACES[$ds]:-(whole datastore)}"; done
 printf 'PBS Raw         : %s/%s\n' "$AP3_OUTPUT_ROOT" "$AP3_RUN_ID"
 printf 'PBS Merged      : %s/%s\n' "$AP3_MERGED_ROOT" "$AP3_RUN_ID"
} | tee "$PRECHECK"

for s in AP3-20-PBSSystem.sh AP3-32-PBSCert.sh AP3-33-PBSAuth.sh AP3-41-PBSStore.sh AP3-42-PBSHealth.sh AP3-43-PBSPerf.sh AP3-52-PBSPrune.sh AP3-53-PBSVerify.sh AP3-54-PBSGC.sh AP3-55-PBSSync.sh AP3-60-RTOEvidence.sh; do
  if ! "${SCRIPT_DIR}/$s"; then printf 'WARN: %s wurde mit Fehler beendet.\n' "$s" >&2; fi
done
if [[ "$AUTO_MERGE" -eq 1 ]]; then
  "${SCRIPT_DIR}/Merge-AP3-PBS.sh" "$AP3_RUN_ID" || printf 'WARN: PBS-Merge mit Fehler beendet.\n' >&2
  "${SCRIPT_DIR}/Build-AP3-PBS-EvidenceIndex.sh" "$AP3_RUN_ID" || printf 'WARN: PBS Evidence_Index mit Fehler beendet.\n' >&2
fi
printf 'AP3 V0.7.2 PBS-Erhebung abgeschlossen. Run-ID: %s\n' "$AP3_RUN_ID"
