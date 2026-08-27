#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - Datastore-Inventar nur fuer PVE-definierten Scope.
set -u
umask 077
SCRIPT_NAME="AP3-41-PBSStore"; SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"; AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"; ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
for ds in "${AP3_SCOPE_DATASTORES[@]}"; do
  scope="$node / datastore $ds"
  cfg="$(awk -v want="$ds" '
    function flush(){if(id==want){print "path|" path;if(gc!="")print "gc-schedule|"gc;if(maint!="")print "maintenance-mode|"maint;if(vn!="")print "verify-new|"vn;ret=0;if(ps!=""){print "prune-schedule|"ps;ret=1}if(kl!=""){print "keep-last|"kl;ret=1}if(kh!=""){print "keep-hourly|"kh;ret=1}if(kd!=""){print "keep-daily|"kd;ret=1}if(kw!=""){print "keep-weekly|"kw;ret=1}if(km!=""){print "keep-monthly|"km;ret=1}if(ky!=""){print "keep-yearly|"ky;ret=1}if(ret==0)print "retention-config|NONE_CONFIGURED"}id=path=gc=maint=vn=ps=kl=kh=kd=kw=km=ky=""}
    /^[[:space:]]*datastore:[[:space:]]+/{if(inx)flush();id=$2;inx=1;next} inx&&/^[^[:space:]]/{flush();inx=0} inx{key=$1;$1="";sub(/^[[:space:]]+/,"",$0);v=$0;if(key=="path")path=v;else if(key=="gc-schedule")gc=v;else if(key=="maintenance-mode")maint=v;else if(key=="verify-new")vn=v;else if(key=="prune-schedule")ps=v;else if(key=="keep-last")kl=v;else if(key=="keep-hourly")kh=v;else if(key=="keep-daily")kd=v;else if(key=="keep-weekly")kw=v;else if(key=="keep-monthly")km=v;else if(key=="keep-yearly")ky=v} END{if(inx)flush()}
  ' "$AP3_PBS_DATASTORE_CFG" 2>/dev/null)"
  if [[ -z "$cfg" ]]; then
    ap3_emit "$scope" "Datastore" "Scope validation" "COLLECTION_FAILED(rc=2): scoped datastore not found in local datastore.cfg" "$AP3_PBS_DATASTORE_CFG; scope filter" "$ts"
    continue
  fi
  ap3_emit "$scope" "Datastore" "Scope validation" "IN_SCOPE" "AP3_PBS_Scope.csv + local datastore.cfg" "$ts"
  while IFS='|' read -r key val; do
    [[ -n "$key" ]] || continue
    case "$key" in
      path)
        ap3_emit "$scope" "Datastore" "Path" "$val" "$AP3_PBS_DATASTORE_CFG whitelist; scoped datastore" "$ts"
        cap="$(df -B1 --output=size,used,avail,pcent,target -- "$val" 2>&1 | tail -n1)"; rc=$?; (( rc==0 )) && ap3_emit "$scope" "Capacity" "Filesystem capacity" "$cap" "local df -B1 <scoped datastore path>" "$ts" || ap3_emit "$scope" "Capacity" "Filesystem capacity" "$(ap3_classify_error "$rc" "$cap")" "local df -B1 <scoped datastore path>" "$ts"
        fs="$(findmnt -no SOURCE,FSTYPE,OPTIONS,TARGET -T "$val" 2>&1)"; rc=$?; (( rc==0 )) && ap3_emit "$scope" "Filesystem" "Filesystem / mount options" "$fs" "local findmnt -T <scoped datastore path>" "$ts" || ap3_emit "$scope" "Filesystem" "Filesystem / mount options" "$(ap3_classify_error "$rc" "$fs")" "local findmnt -T <scoped datastore path>" "$ts"
        ;;
      gc-schedule) ap3_emit "$scope" "GC" "GC schedule" "$val" "$AP3_PBS_DATASTORE_CFG whitelist" "$ts" ;;
      maintenance-mode) ap3_emit "$scope" "Health" "Maintenance mode" "$val" "$AP3_PBS_DATASTORE_CFG whitelist" "$ts" ;;
      verify-new) ap3_emit "$scope" "Verify" "Verify new backups" "$val" "$AP3_PBS_DATASTORE_CFG whitelist" "$ts" ;;
      prune-schedule) ap3_emit "$scope" "Retention" "prune-schedule" "$val" "$AP3_PBS_DATASTORE_CFG whitelist" "$ts" ;;
      keep-*) ap3_emit "$scope" "Retention" "$key" "$val" "$AP3_PBS_DATASTORE_CFG whitelist" "$ts" ;;
      retention-config) ap3_emit "$scope" "Retention" "Datastore retention parameters" "$val" "$AP3_PBS_DATASTORE_CFG whitelist" "$ts" ;;
    esac
  done <<< "$cfg"
done
} > "$OUT_FILE"; printf '%s\n' "$OUT_FILE"
