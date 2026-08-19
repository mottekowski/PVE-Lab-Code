#!/usr/bin/env bash
# AP1 3.2 - Topologie, Failure Domains, OSD Layout
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "Ceph_Cluster" "08" "CephCluster" "CephTopology"
CATEGORY="Topologie / Failure Domains / OSD Layout"
SCOPE="Ceph-Cluster via ${HOST_SHORT}"

run_capture "osd-tree-json" "ceph osd tree -f json" ceph osd tree -f json
if run_ready "$SCOPE" "$CATEGORY" "OSD Tree" "ceph osd tree -f json"; then
    json_array_fields "$RUN_STDOUT" nodes name id type status reweight crush_weight device_class children | while IFS=$'\t' read -r name field value; do emit_record "$SCOPE" "$CATEGORY" "CRUSH Node / $name / $field" "$value" "ceph osd tree" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "osd-df-json" "ceph osd df -f json" ceph osd df -f json
if run_ready "$SCOPE" "$CATEGORY" "OSD DF" "ceph osd df -f json"; then
    json_array_fields "$RUN_STDOUT" nodes id device_class name kb kb_used kb_avail utilization var pgs status reweight weight | while IFS=$'\t' read -r id field value; do emit_record "OSD $id" "$CATEGORY" "OSD DF / $field" "$value" "ceph osd df" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "device-classes-json" "ceph osd crush class ls -f json" ceph osd crush class ls -f json
if run_ready "$SCOPE" "$CATEGORY" "Device Klassen" "ceph osd crush class ls -f json"; then
    classes="$(perl -MJSON::PP -0777 -e '$d=decode_json(<>); print join(",", @$d)' < "$RUN_STDOUT")"; emit_record "$SCOPE" "$CATEGORY" "Device Classes" "$classes" "ceph osd crush class ls" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
fi

run_capture "crush-tree-json" "ceph osd crush tree --format json-pretty" ceph osd crush tree --format json-pretty
if run_ready "$SCOPE" "$CATEGORY" "CRUSH Tree JSON" "ceph osd crush tree --format json-pretty"; then
    json_array_fields "$RUN_STDOUT" nodes name id type type_id children device_class | while IFS=$'\t' read -r name field value; do emit_record "$SCOPE" "$CATEGORY" "CRUSH Tree / $name / $field" "$value" "ceph osd crush tree --format json-pretty" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "crush-rule-list" "ceph osd crush rule ls" ceph osd crush rule ls
if run_ready "$SCOPE" "$CATEGORY" "CRUSH Rules - Liste" "ceph osd crush rule ls"; then n=0; while IFS= read -r rule; do [[ -z "$rule" ]]&&continue; n=$((n+1)); emit_record "$SCOPE" "$CATEGORY" "CRUSH Rule $n / Name" "$rule" "ceph osd crush rule ls" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done < "$RUN_STDOUT"; fi

run_capture "crush-rule-dump" "ceph osd crush rule dump" ceph osd crush rule dump
if run_ready "$SCOPE" "$CATEGORY" "CRUSH Rules - Dump" "ceph osd crush rule dump"; then
    json_array_fields "$RUN_STDOUT" . rule_name rule_id type min_size max_size steps | while IFS=$'\t' read -r rule field value; do emit_record "$SCOPE" "$CATEGORY" "CRUSH Rule / $rule / $field" "$value" "ceph osd crush rule dump" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

# The source document displays a 200-line sample. The collector captures the complete read-only JSON first,
# then normalizes only selected metadata fields so the JSON is not broken by a pipe to head.
run_capture "osd-metadata" "ceph osd metadata (Source: ceph osd metadata | head -n 200)" ceph osd metadata
if run_ready "$SCOPE" "$CATEGORY" "OSD Metadata" "ceph osd metadata (Source: ceph osd metadata | head -n 200)"; then
    if perl -MJSON::PP -0777 -e 'eval{decode_json(<>)}; exit($@?1:0)' < "$RUN_STDOUT"; then
        json_array_fields "$RUN_STDOUT" . id hostname osd_objectstore rotational devices bluefs bluestore_bdev_type bluestore_bdev_size ceph_version arch kernel_version | while IFS=$'\t' read -r id field value; do emit_record "OSD $id" "$CATEGORY" "Metadata / $field" "$value" "ceph osd metadata" "$RUN_TS" "Read-only; selected non-secret fields; Source cheat-sheet shows head -n 200; Evidence=${RUN_EVIDENCE_REL}"; done
    else
        emit_status "$SCOPE" "$CATEGORY" "OSD Metadata" "INVALID_JSON" "ceph osd metadata" "$RUN_TS" "Metadata output could not be parsed as JSON; Evidence=${RUN_EVIDENCE_REL}"
    fi
fi
finish_collector
