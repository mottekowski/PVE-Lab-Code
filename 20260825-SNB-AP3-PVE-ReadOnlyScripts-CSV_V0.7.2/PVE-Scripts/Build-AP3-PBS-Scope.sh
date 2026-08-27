#!/usr/bin/env bash
# Erzeugt den manuellen PVE->PBS Scope-Handoff fuer AP3 V0.7.2.
# Nur nicht-sensitive Selektoren; keine Credentials/User/Token-IDs.
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ap3-pve.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"
MERGED_ROOT="${AP3_MERGED_ROOT:-${SCRIPT_DIR}/PVE-Merged}"
PVE_STORAGE_CFG="${AP3_PVE_STORAGE_CFG:-/etc/pve/storage.cfg}"
OUT_DIR="${MERGED_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${RUN_ID}_AP3_PBS_Scope.csv"
mkdir -p "$OUT_DIR"
cluster="$(pvecm status 2>/dev/null | awk -F: '/^[[:space:]]*Name:/{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2);print $2;exit}' || true)"
[[ -n "$cluster" ]] || cluster="PVE_CLUSTER_UNRESOLVED"
{
  printf '"PVE-Cluster";"PVE-Storage-ID";"PBS-Server";"PBS-Datastore";"PBS-Namespace"\n'
  awk -v cluster="$cluster" '
    function q(s){gsub(/"/,"\"\"",s);return "\"" s "\""}
    function flush(){if(id!=""&&server!=""&&datastore!="")print q(cluster) ";" q(id) ";" q(server) ";" q(datastore) ";" q(namespace);id=server=datastore=namespace=""}
    /^[[:space:]]*pbs:[[:space:]]+/{if(inpbs)flush();id=$2;inpbs=1;next}
    inpbs&&/^[^[:space:]]/{flush();inpbs=0}
    inpbs{key=$1;$1="";sub(/^[[:space:]]+/,"",$0);v=$0;if(key=="server")server=v;else if(key=="datastore")datastore=v;else if(key=="namespace")namespace=v}
    END{if(inpbs)flush()}
  ' "$PVE_STORAGE_CFG" 2>/dev/null
} > "$OUT_FILE"
if [[ $(wc -l < "$OUT_FILE") -le 1 ]]; then
  printf 'ERROR: Kein nutzbarer PBS-Scope aus %s ermittelt.\n' "$PVE_STORAGE_CFG" >&2
  exit 3
fi
printf '%s\n' "$OUT_FILE"
