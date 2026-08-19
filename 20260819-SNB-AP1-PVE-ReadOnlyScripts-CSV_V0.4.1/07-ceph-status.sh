#!/usr/bin/env bash
# AP1 3.1 - Ceph Überblick & Status
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "Ceph_Cluster" "07" "CephCluster" "CephStatus"
CATEGORY="Überblick & Status"
SCOPE="Ceph-Cluster via ${HOST_SHORT}"

run_capture "ceph-status" "ceph -s" ceph -s
if run_ready "$SCOPE" "$CATEGORY" "Cluster Status" "ceph -s"; then
    awk '
      /^[[:space:]]{2}[a-zA-Z]+:/ {section=$0; sub(/^[[:space:]]+/,"",section); sub(/:.*$/,"",section); next}
      /^[[:space:]]{4}[^:]+:/ {line=$0; sub(/^[[:space:]]+/,"",line); pos=index(line,":"); k=substr(line,1,pos-1); v=substr(line,pos+1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print section "/" k "\t" v}
    ' "$RUN_STDOUT" | while IFS=$'\t' read -r path value; do emit_record "$SCOPE" "$CATEGORY" "Cluster Status / $path" "$value" "ceph -s" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "ceph-health-detail" "ceph health detail" ceph health detail
if run_ready "$SCOPE" "$CATEGORY" "Health Detail" "ceph health detail"; then
    n=0; while IFS= read -r line; do [[ -z "$line" ]] && continue; n=$((n+1)); param="Health"; [[ $n -gt 1 ]] && param="Health Detail $((n-1))"; emit_record "$SCOPE" "$CATEGORY" "$param" "$line" "ceph health detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done < "$RUN_STDOUT"
fi

run_capture "ceph-version" "ceph version" ceph version
if run_ready "$SCOPE" "$CATEGORY" "Version" "ceph version"; then emit_record "$SCOPE" "$CATEGORY" "Ceph Version" "$(head -n1 "$RUN_STDOUT")" "ceph version" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; fi

run_capture "mon-stat" "ceph mon stat" ceph mon stat
if run_ready "$SCOPE" "$CATEGORY" "MON Status" "ceph mon stat"; then
    line="$(head -n1 "$RUN_STDOUT")"; emit_record "$SCOPE" "$CATEGORY" "MON / Summary" "$line" "ceph mon stat" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    if [[ "$line" =~ ^e([0-9]+):[[:space:]]+([0-9]+)[[:space:]]+mons ]]; then emit_record "$SCOPE" "$CATEGORY" "MON / Epoch" "${BASH_REMATCH[1]}" "ceph mon stat" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; emit_record "$SCOPE" "$CATEGORY" "MON / Count" "${BASH_REMATCH[2]}" "ceph mon stat" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; fi
fi

run_capture "mgr-stat" "ceph mgr stat" ceph mgr stat
if run_ready "$SCOPE" "$CATEGORY" "MGR Status" "ceph mgr stat"; then
    if head -c1 "$RUN_STDOUT" | grep -q '[{[]'; then json_object_fields "$RUN_STDOUT" epoch available active_name num_standby | while IFS=$'\t' read -r f v; do emit_record "$SCOPE" "$CATEGORY" "MGR / $f" "$v" "ceph mgr stat" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done; else emit_record "$SCOPE" "$CATEGORY" "MGR / Summary" "$(tr '\n' ' ' < "$RUN_STDOUT")" "ceph mgr stat" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; fi
fi

run_capture "quorum-status-json" "ceph quorum_status -f json-pretty" ceph quorum_status -f json-pretty
if run_ready "$SCOPE" "$CATEGORY" "Quorum JSON" "ceph quorum_status -f json-pretty"; then
    json_object_fields "$RUN_STDOUT" election_epoch quorum_age quorum quorum_names monmap.epoch monmap.fsid monmap.min_mon_release_name | while IFS=$'\t' read -r f v; do emit_record "$SCOPE" "$CATEGORY" "Quorum / $f" "$v" "ceph quorum_status -f json-pretty" "$RUN_TS" "Selected scalar only; full JSON in Evidence=${RUN_EVIDENCE_REL}"; done
fi
finish_collector
