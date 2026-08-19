#!/usr/bin/env bash
# AP1 2.1 - Allgemein / Versionierung
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "ProxMox_Cluster" "01" "ProxMoxCluster" "PVEInfo"
CATEGORY="Allgemein / Versionierung"
CLUSTER_SCOPE="PVE-Cluster via ${HOST_SHORT}"
NODE="${NODE:-$HOST_SHORT}"

run_capture "pveversion" "pveversion -v" pveversion -v
if run_ready "$HOST_SHORT" "$CATEGORY" "Version/Kernel" "pveversion -v"; then
    awk -F': ' 'NF>=2 {k=$1; sub(/^[[:space:]]+|[[:space:]]+$/, "", k); v=substr($0,index($0,": ")+2); print k "\t" v}' "$RUN_STDOUT" |
    while IFS=$'\t' read -r k v; do
        emit_record "$HOST_SHORT" "$CATEGORY" "Package / $k" "$v" "pveversion -v" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

run_capture "pvecm-status" "pvecm status" pvecm status
if run_ready "$CLUSTER_SCOPE" "$CATEGORY" "Cluster-Status" "pvecm status"; then
    awk '
      BEGIN{membership=0}
      /^Membership information/ {membership=1; next}
      membership==0 {
        line=$0; pos=index(line,":");
        if(pos>0){k=substr(line,1,pos-1);v=substr(line,pos+1);gsub(/^[ \t]+|[ \t]+$/,"",k);gsub(/^[ \t]+|[ \t]+$/,"",v);if(k!=""&&v!="") print "KV\t" k "\t" v}
      }
      membership==1 && $1 ~ /^0x[0-9A-Fa-f]+$/ {local=($0 ~ /\(local\)/)?"Y":"N"; print "MEM\t" $1 "\t" $2 "\t" $3 "\t" local}
    ' "$RUN_STDOUT" | while IFS=$'\t' read -r typ a b c d; do
        if [[ "$typ" == "KV" ]]; then
            emit_record "$CLUSTER_SCOPE" "$CATEGORY" "Cluster / $a" "$b" "pvecm status" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        else
            emit_record "$CLUSTER_SCOPE" "$CATEGORY" "Membership / ${c} / NodeID" "$a" "pvecm status" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
            emit_record "$CLUSTER_SCOPE" "$CATEGORY" "Membership / ${c} / Votes" "$b" "pvecm status" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
            emit_record "$CLUSTER_SCOPE" "$CATEGORY" "Membership / ${c} / Local" "$d" "pvecm status" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        fi
    done
fi

run_capture "nodes-json" "pvesh get /nodes --output-format json" pvesh get /nodes --output-format json
if run_ready "$CLUSTER_SCOPE" "$CATEGORY" "Node-Info" "pvesh get /nodes --output-format json"; then
    json_array_fields "$RUN_STDOUT" . node status cpu maxcpu maxmem mem uptime level | while IFS=$'\t' read -r entity field value; do
        case "$field" in maxmem|mem) field="${field} (bytes)";; esac
        emit_record "$entity" "$CATEGORY" "Node / $field" "$value" "pvesh get /nodes" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

run_capture "timedatectl" "timedatectl" timedatectl
if run_ready "$HOST_SHORT" "$CATEGORY" "NTP/Zeitsync" "timedatectl"; then
    emit_kv_colon_file "$HOST_SHORT" "$CATEGORY" "Time" "timedatectl" "$RUN_TS" "$RUN_STDOUT" "Read-only"
fi

run_capture "chrony-sources" "chronyc sources -v" chronyc sources -v
if run_ready "$HOST_SHORT" "$CATEGORY" "Chrony Sources" "chronyc sources -v"; then
    awk '$1 ~ /^[\^=#][*+\-x~?]/ {state=substr($1,1,2); name=$2; print name "\tState\t" state; print name "\tStratum\t" $3; print name "\tPoll\t" $4; print name "\tReach\t" $5; print name "\tLastRx\t" $6; sample=""; for(i=7;i<=NF;i++) sample=sample (i==7?"":" ") $i; print name "\tLast sample\t" sample}' "$RUN_STDOUT" |
    while IFS=$'\t' read -r src field value; do
        emit_record "$HOST_SHORT" "$CATEGORY" "Chrony / ${src} / ${field}" "$value" "chronyc sources -v" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

run_capture "subscription-json" "pvesh get /nodes/<NODE>/subscription --output-format json" pvesh get "/nodes/${NODE}/subscription" --output-format json
if run_ready "$NODE" "$CATEGORY" "Subscription" "pvesh get /nodes/<NODE>/subscription --output-format json"; then
    json_object_fields "$RUN_STDOUT" status level message | while IFS=$'\t' read -r field value; do
        emit_record "$NODE" "$CATEGORY" "Subscription / $field" "$value" "pvesh get /nodes/<NODE>/subscription" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi
finish_collector
