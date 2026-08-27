#!/usr/bin/env bash
# AP1 3.3 - Pools & Datenmodelle (RBD/CephFS)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "Ceph_Cluster" "09" "CephCluster" "CephPools"
CATEGORY="Pools / Datenmodelle"
SCOPE="Ceph-Cluster via ${HOST_SHORT}"
RBD_INFO_LIMIT="${RBD_INFO_LIMIT:-100}"

declare -a POOLS=()
declare -A POOL_APP=()
run_capture "pool-list-detail" "ceph osd pool ls detail" ceph osd pool ls detail
if run_ready "$SCOPE" "$CATEGORY" "Pool Liste" "ceph osd pool ls detail"; then
    while IFS=$'\t' read -r id name type size minsize crush pgnum pgpnum autoscale flags app; do
        POOLS+=("$name"); POOL_APP["$name"]="$app"
        emit_record "Pool $name" "$CATEGORY" "Pool / ID" "$id" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        emit_record "Pool $name" "$CATEGORY" "Pool / Type" "$type" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        [[ -n "$size" ]] && emit_record "Pool $name" "$CATEGORY" "Pool / size" "$size" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        [[ -n "$minsize" ]] && emit_record "Pool $name" "$CATEGORY" "Pool / min_size" "$minsize" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        [[ -n "$crush" ]] && emit_record "Pool $name" "$CATEGORY" "Pool / crush_rule" "$crush" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        [[ -n "$pgnum" ]] && emit_record "Pool $name" "$CATEGORY" "Pool / pg_num" "$pgnum" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        [[ -n "$pgpnum" ]] && emit_record "Pool $name" "$CATEGORY" "Pool / pgp_num" "$pgpnum" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        [[ -n "$autoscale" ]] && emit_record "Pool $name" "$CATEGORY" "Pool / autoscale_mode" "$autoscale" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        [[ -n "$flags" ]] && emit_record "Pool $name" "$CATEGORY" "Pool / flags" "$flags" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        [[ -n "$app" ]] && emit_record "Pool $name" "$CATEGORY" "Pool / application" "$app" "ceph osd pool ls detail" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done < <(perl -ne '
      if(/^pool\s+(\d+)\s+\x27([^\x27]+)\x27\s+(\w+)/){
        $id=$1; $n=$2; $t=$3; $x=$_;
        @keys=("size","min_size","crush_rule","pg_num","pgp_num","autoscale_mode","flags","application");
        %v=();
        for $k (@keys) { $v{$k}=($x =~ /\b\Q$k\E\s+(\S+)/) ? $1 : ""; }
        print join("\t",$id,$n,$t,@v{@keys}),"\n";
      }
    ' "$RUN_STDOUT")
fi

for pool in "${POOLS[@]}"; do
    for setting in size min_size; do
        run_capture "pool-${pool}-${setting}" "ceph osd pool get <POOL> ${setting}" ceph osd pool get "$pool" "$setting"
        if run_ready "Pool $pool" "$CATEGORY" "Pool Settings - ${setting}" "ceph osd pool get <POOL> ${setting}"; then
            value="$(awk -F: 'NF>=2 {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}' "$RUN_STDOUT")"; [[ -z "$value" ]] && value="$(awk '{print $NF; exit}' "$RUN_STDOUT")"
            emit_record "Pool $pool" "$CATEGORY" "Pool Setting / $setting" "$value" "ceph osd pool get <POOL> ${setting}" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        fi
    done
done

run_capture "autoscale-status" "ceph osd pool autoscale-status" ceph osd pool autoscale-status
if run_ready "$SCOPE" "$CATEGORY" "Autoscaler" "ceph osd pool autoscale-status"; then
    awk 'NR>1 && NF {pool=$1; line=$0; sub(/^[[:space:]]+/,"",line); sub(/^[^[:space:]]+[[:space:]]+/,"",line); print pool "\t" line}' "$RUN_STDOUT" | while IFS=$'\t' read -r pool line; do emit_record "Pool $pool" "$CATEGORY" "Autoscaler / Summary" "$line" "ceph osd pool autoscale-status" "$RUN_TS" "Normalized as one short record per pool; Evidence=${RUN_EVIDENCE_REL}"; done
fi

for pool in "${POOLS[@]}"; do
    [[ "${POOL_APP[$pool]}" == *rbd* ]] || continue
    run_capture "rbd-ls-${pool}" "rbd ls -p <POOL>" rbd ls -p "$pool"
    if [[ $RUN_RC -ne 0 ]]; then run_ready "Pool $pool" "$CATEGORY" "RBD Images" "rbd ls -p <POOL>" || true; continue; fi
    mapfile -t IMAGES < <(sed '/^[[:space:]]*$/d' "$RUN_STDOUT")
    emit_record "Pool $pool" "$CATEGORY" "RBD / Image count" "${#IMAGES[@]}" "rbd ls -p <POOL>" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    idx=0
    for image in "${IMAGES[@]}"; do
        idx=$((idx+1)); emit_record "Pool $pool" "$CATEGORY" "RBD Image $idx / Name" "$image" "rbd ls -p <POOL>" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        if [[ "$RBD_INFO_LIMIT" != 0 && $idx -gt $RBD_INFO_LIMIT ]]; then continue; fi
        run_capture "rbd-info-${pool}-${idx}" "rbd info -p <POOL> <IMAGE>" rbd info -p "$pool" "$image"
        if run_ready "RBD ${pool}/${image}" "$CATEGORY" "RBD Info" "rbd info -p <POOL> <IMAGE>"; then
            awk '
              /^[[:space:]]*rbd image/ {next}
              /^[[:space:]]*size[[:space:]]+/ {line=$0; sub(/^[[:space:]]*size[[:space:]]+/,"",line); print "Size\t" line; next}
              /^[[:space:]]*order[[:space:]]+/ {line=$0; sub(/^[[:space:]]*order[[:space:]]+/,"",line); print "Order\t" line; next}
              /:/ {line=$0; sub(/^[[:space:]]+/,"",line); pos=index(line,":"); k=substr(line,1,pos-1); v=substr(line,pos+1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",k);gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); if(k!=""&&v!="") print k "\t" v}
            ' "$RUN_STDOUT" | while IFS=$'\t' read -r field value; do emit_record "RBD ${pool}/${image}" "$CATEGORY" "RBD Info / $field" "$value" "rbd info -p <POOL> <IMAGE>" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
        fi
    done
    if [[ "$RBD_INFO_LIMIT" != 0 && ${#IMAGES[@]} -gt $RBD_INFO_LIMIT ]]; then emit_status "Pool $pool" "$CATEGORY" "RBD Info" "CAPPED" "rbd info -p <POOL> <IMAGE>" "$(date --iso-8601=seconds)" "Detailed rbd info capped at ${RBD_INFO_LIMIT} images; set RBD_INFO_LIMIT=0 for unlimited"; fi
done

run_capture "cephfs-status" "ceph fs status" ceph fs status
if [[ $RUN_RC -ne 0 ]]; then run_ready "$SCOPE" "$CATEGORY" "CephFS Status" "ceph fs status" || true
elif [[ ! -s "$RUN_STDOUT" ]]; then emit_no_data "$SCOPE" "$CATEGORY" "CephFS Status" "ceph fs status" "$RUN_TS" "No CephFS status output"
else n=0; while IFS= read -r line; do [[ -z "$line" ]]&&continue; n=$((n+1)); emit_record "$SCOPE" "$CATEGORY" "CephFS / Status $n" "$line" "ceph fs status" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done < "$RUN_STDOUT"; fi

run_capture "mds-stat" "ceph mds stat" ceph mds stat
if [[ $RUN_RC -ne 0 ]]; then run_ready "$SCOPE" "$CATEGORY" "MDS Status" "ceph mds stat" || true
elif [[ ! -s "$RUN_STDOUT" ]]; then emit_no_data "$SCOPE" "$CATEGORY" "MDS Status" "ceph mds stat" "$RUN_TS" "No MDS status output"
else emit_record "$SCOPE" "$CATEGORY" "MDS / Summary" "$(tr '\n' ' ' < "$RUN_STDOUT")" "ceph mds stat" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; fi
finish_collector
