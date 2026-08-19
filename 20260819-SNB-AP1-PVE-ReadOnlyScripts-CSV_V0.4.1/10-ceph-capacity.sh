#!/usr/bin/env bash
# AP1 3.4 - Kapazität & Schwellenwerte
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "Ceph_Cluster" "10" "CephCluster" "CephCapacity"
CATEGORY="Kapazität & Schwellenwerte"
SCOPE="Ceph-Cluster via ${HOST_SHORT}"

run_capture "ceph-df-json" "ceph df -f json" ceph df -f json
declare -a POOLS=()
if run_ready "$SCOPE" "$CATEGORY" "Cluster DF" "ceph df -f json"; then
    json_object_fields "$RUN_STDOUT" stats.total_bytes stats.total_avail_bytes stats.total_used_bytes stats.total_used_raw_bytes stats.total_used_raw_ratio | while IFS=$'\t' read -r f v; do emit_record "$SCOPE" "$CATEGORY" "Capacity / $f" "$v" "ceph df" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
    json_array_fields "$RUN_STDOUT" pools name id stats.stored stats.objects stats.kb_used stats.bytes_used stats.percent_used stats.max_avail | while IFS=$'\t' read -r pool f v; do emit_record "Pool $pool" "$CATEGORY" "Capacity / $f" "$v" "ceph df" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
    mapfile -t POOLS < <(perl -MJSON::PP -0777 -e '$d=decode_json(<>); for $p (@{$d->{pools}||[]}) { print $p->{name},"\n" if defined $p->{name}; }' < "$RUN_STDOUT")
fi

# The source document marks the direct "ceph config get mon ...ratio" commands red.
# V0.3 therefore does NOT execute those commands. The same read-only threshold values
# are derived from the already supported read-only "ceph osd dump" output instead.
run_capture "osd-dump-thresholds" "ceph osd dump" ceph osd dump
if run_ready "$SCOPE" "$CATEGORY" "Nearfull/Full Thresholds" "ceph osd dump"; then
    found=0
    while IFS=$'\t' read -r key value; do
        [[ -z "$key" ]] && continue
        found=1
        case "$key" in
            nearfull_ratio) param="Threshold / Nearfull ratio" ;;
            full_ratio) param="Threshold / Full ratio" ;;
            *) continue ;;
        esac
        emit_record "$SCOPE" "$CATEGORY" "$param" "$value" "ceph osd dump" "$RUN_TS" "Read-only alternative to red-marked direct config-get command; Evidence=${RUN_EVIDENCE_REL}"
    done < <(awk '$1=="nearfull_ratio" || $1=="full_ratio" {print $1 "\t" $2}' "$RUN_STDOUT")
    if [[ $found -eq 0 ]]; then
        emit_status "$SCOPE" "$CATEGORY" "Nearfull/Full Thresholds" "NO_DATA" "ceph osd dump" "$RUN_TS" "Threshold fields not present in ceph osd dump output; red-marked direct config-get command remains excluded; Evidence=${RUN_EVIDENCE_REL}"
    fi
fi

run_capture "pg-stat" "ceph pg stat" ceph pg stat
if run_ready "$SCOPE" "$CATEGORY" "PG Summary" "ceph pg stat"; then emit_record "$SCOPE" "$CATEGORY" "PG Summary" "$(tr '\n' ' ' < "$RUN_STDOUT")" "ceph pg stat" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; fi

for pool in "${POOLS[@]}"; do
    [[ -z "$pool" ]] && continue
    run_capture "quota-$(printf '%s' "$pool" | tr -c 'A-Za-z0-9._-' '_')" "ceph osd pool get-quota <POOL>" ceph osd pool get-quota "$pool"
    if ! run_ready "Pool $pool" "$CATEGORY" "Pool Quota" "ceph osd pool get-quota <POOL>"; then continue; fi
    line="$(tr '\n' ' ' < "$RUN_STDOUT")"
    if [[ "$line" =~ max[[:space:]]objects:[[:space:]]*([^[:space:]]+) ]]; then emit_record "Pool $pool" "$CATEGORY" "Quota / Max objects" "${BASH_REMATCH[1]}" "ceph osd pool get-quota <POOL>" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; fi
    if [[ "$line" =~ max[[:space:]]bytes:[[:space:]]*([^[:space:]]+) ]]; then emit_record "Pool $pool" "$CATEGORY" "Quota / Max bytes" "${BASH_REMATCH[1]}" "ceph osd pool get-quota <POOL>" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; fi
    if [[ ! "$line" =~ max[[:space:]]objects: && ! "$line" =~ max[[:space:]]bytes: ]]; then emit_record "Pool $pool" "$CATEGORY" "Quota / Summary" "$line" "ceph osd pool get-quota <POOL>" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; fi
done
finish_collector
