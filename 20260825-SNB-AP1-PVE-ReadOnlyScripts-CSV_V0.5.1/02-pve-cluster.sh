#!/usr/bin/env bash
# AP1 2.2 - Cluster & Quorum (Corosync)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "ProxMox_Cluster" "02" "ProxMoxCluster" "PVECluster"
CATEGORY="Cluster & Quorum (Corosync)"
SCOPE="PVE-Cluster via ${HOST_SHORT}"

run_capture "corosync-conf" "cat /etc/pve/corosync.conf" cat /etc/pve/corosync.conf
if run_ready "$SCOPE" "$CATEGORY" "Corosync Konfig" "cat /etc/pve/corosync.conf"; then
    awk '
      BEGIN{depth=0; nodeidx=0; ifaceidx=0}
      /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
      /\{[[:space:]]*$/ {
        line=$0; sub(/^[[:space:]]+/,"",line); sub(/[[:space:]]*\{[[:space:]]*$/,"",line)
        depth++; name=line
        if(name=="node"){nodeidx++; name="node[" nodeidx "]"}
        else if(name=="interface"){ifaceidx++; name="interface[" ifaceidx "]"}
        ctx[depth]=name; next
      }
      /^[[:space:]]*\}/ {delete ctx[depth]; depth--; next}
      /:/ {
        line=$0; sub(/^[[:space:]]+/,"",line); pos=index(line,":"); k=substr(line,1,pos-1); v=substr(line,pos+1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",k);gsub(/^[[:space:]]+|[[:space:]]+$/,"",v)
        p=""; for(i=1;i<=depth;i++) if(ctx[i]!="") p=p (p?"/":"") ctx[i]
        print p "/" k "\t" v
      }
    ' "$RUN_STDOUT" | while IFS=$'\t' read -r path value; do
        emit_record "$SCOPE" "$CATEGORY" "Corosync / $path" "$value" "cat /etc/pve/corosync.conf" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

run_capture "pvecm-nodes" "pvecm nodes" pvecm nodes
if run_ready "$SCOPE" "$CATEGORY" "Membership" "pvecm nodes"; then
    awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {name=$3; local=($0~/\(local\)/)?"Y":"N"; print name "\tNodeID\t" $1; print name "\tVotes\t" $2; print name "\tLocal\t" local}' "$RUN_STDOUT" |
    while IFS=$'\t' read -r node field value; do
        emit_record "$SCOPE" "$CATEGORY" "Membership / $node / $field" "$value" "pvecm nodes" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

run_capture "corosync-link-status" "corosync-cfgtool -s" corosync-cfgtool -s
if run_ready "$SCOPE" "$CATEGORY" "Netz-Test" "corosync-cfgtool -s"; then
    awk '
      /^Local node ID/ {print "Local Node / Summary\t" $0; next}
      /^LINK ID/ {link=$3; print "Link " link " / Protocol\t" $4; next}
      /^[[:space:]]*addr[[:space:]]*=/ {v=$0; sub(/^.*=[[:space:]]*/,"",v); print "Link " link " / Address\t" v; next}
      /^[[:space:]]*nodeid:/ {line=$0; gsub(/^[[:space:]]+/,"",line); split(line,a,":"); id=a[2]; gsub(/[[:space:]]/,"",id); status=a[3]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",status); print "Link " link " / Node " id " / Status\t" status}
    ' "$RUN_STDOUT" | while IFS=$'\t' read -r param value; do
        emit_record "$SCOPE" "$CATEGORY" "$param" "$value" "corosync-cfgtool -s" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi
# pvecm expected is deliberately excluded: it can change expected votes.
finish_collector
