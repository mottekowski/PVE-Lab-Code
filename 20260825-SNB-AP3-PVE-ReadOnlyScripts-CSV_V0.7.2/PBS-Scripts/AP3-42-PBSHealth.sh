#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - Storage-/Filesystem-Health fuer scoped Datastores.
# Keine globale Device-Inventarisierung anderer Datastores.
set -u
umask 077
SCRIPT_NAME="AP3-42-PBSHealth"; SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"; AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"; ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
for ds in "${AP3_SCOPE_DATASTORES[@]}"; do
  scope="$node / datastore $ds"; path="$(ap3_datastore_path "$ds")"
  if [[ -z "$path" ]]; then ap3_emit "$scope" "Health" "Datastore path" "COLLECTION_FAILED(rc=2): scoped datastore path not found" "$AP3_PBS_DATASTORE_CFG" "$ts"; continue; fi
  fsline="$(findmnt -no SOURCE,FSTYPE,OPTIONS,TARGET -T "$path" 2>&1)"; rc=$?
  if (( rc != 0 )); then ap3_emit "$scope" "Filesystem" "Scoped mount" "$(ap3_classify_error "$rc" "$fsline")" "findmnt -T <scoped datastore path>" "$ts"; continue; fi
  ap3_emit "$scope" "Filesystem" "Scoped mount" "$fsline" "findmnt -T <scoped datastore path>" "$ts"
  src="$(findmnt -no SOURCE -T "$path" 2>/dev/null | head -n1)"; fstype="$(findmnt -no FSTYPE -T "$path" 2>/dev/null | head -n1)"
  dfv="$(df -hT -- "$path" 2>&1)"; rc=$?; (( rc==0 )) && ap3_emit "$scope" "Filesystem" "Filesystem usage" "$dfv" "df -hT <scoped datastore path>" "$ts" || ap3_emit "$scope" "Filesystem" "Filesystem usage" "$(ap3_classify_error "$rc" "$dfv")" "df -hT <scoped datastore path>" "$ts"
  if [[ "$src" == /dev/* ]] && command -v lsblk >/dev/null 2>&1; then
    devv="$(lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS "$src" 2>&1)"; rc=$?; (( rc==0 )) && ap3_emit "$scope" "Storage" "Backing block device" "$devv" "lsblk <scoped mount source>; serial/UUID excluded" "$ts" || ap3_emit "$scope" "Storage" "Backing block device" "$(ap3_classify_error "$rc" "$devv")" "lsblk <scoped mount source>" "$ts"
  else
    ap3_emit "$scope" "Storage" "Backing block device" "NOT_APPLICABLE: no direct /dev source resolved" "findmnt SOURCE" "$ts"
  fi
  if [[ "${fstype,,}" == zfs ]]; then
    dataset="$src"; pool="${dataset%%/*}"
    if command -v zpool >/dev/null 2>&1; then
      zv="$(zpool status "$pool" 2>&1 | sed -E 's#/dev/disk/by-id/[^ ]+#/dev/disk/by-id/REDACTED#g; s#(ata|wwn)-[A-Za-z0-9_.:-]+#DEVICE-ID-REDACTED#g')"; rc=${PIPESTATUS[0]:-0}; (( rc==0 )) && ap3_emit "$scope" "Health" "ZFS pool status" "$zv" "zpool status <scoped pool>; device IDs redacted" "$ts" || ap3_emit "$scope" "Health" "ZFS pool status" "$(ap3_classify_error "$rc" "$zv")" "zpool status <scoped pool>" "$ts"
    else ap3_emit "$scope" "Health" "ZFS pool status" "NOT_SUPPORTED" "zpool" "$ts"; fi
    if command -v zfs >/dev/null 2>&1; then
      zfv="$(zfs list -o name,used,avail,refer,mountpoint "$dataset" 2>&1)"; rc=$?; (( rc==0 )) && ap3_emit "$scope" "Storage" "ZFS dataset" "$zfv" "zfs list <scoped dataset>" "$ts" || ap3_emit "$scope" "Storage" "ZFS dataset" "$(ap3_classify_error "$rc" "$zfv")" "zfs list <scoped dataset>" "$ts"
    else ap3_emit "$scope" "Storage" "ZFS dataset" "NOT_SUPPORTED" "zfs" "$ts"; fi
  else
    ap3_emit "$scope" "Health" "ZFS pool status" "NOT_APPLICABLE: scoped datastore filesystem=${fstype:-unknown}" "findmnt FSTYPE" "$ts"
    ap3_emit "$scope" "Storage" "ZFS dataset" "NOT_APPLICABLE: scoped datastore filesystem=${fstype:-unknown}" "findmnt FSTYPE" "$ts"
  fi
  if [[ "$src" == /dev/md* ]] && command -v mdadm >/dev/null 2>&1; then
    mdv="$(mdadm --detail "$src" 2>&1)"; rc=$?; (( rc==0 )) && ap3_emit "$scope" "Health" "Software RAID status" "$mdv" "mdadm --detail <scoped md device>" "$ts" || ap3_emit "$scope" "Health" "Software RAID status" "$(ap3_classify_error "$rc" "$mdv")" "mdadm --detail <scoped md device>" "$ts"
  else ap3_emit "$scope" "Health" "Software RAID status" "NOT_APPLICABLE: scoped mount source is not an md device" "findmnt SOURCE" "$ts"; fi
  ap3_emit "$scope" "Health" "SMART device discovery" "NOT_EXECUTED: device-level SMART is not automatically exported without unambiguous datastore-to-physical-device mapping" "scope isolation rule" "$ts"
done
} > "$OUT_FILE"; printf '%s\n' "$OUT_FILE"
