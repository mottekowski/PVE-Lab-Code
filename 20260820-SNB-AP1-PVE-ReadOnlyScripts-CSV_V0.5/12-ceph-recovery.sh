#!/usr/bin/env bash
# AP1 3.6 - Recovery / Scrub / Flags
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "Ceph_Cluster" "12" "CephCluster" "CephRecovery"
CATEGORY="Recovery / Scrub / Flags"
SCOPE="Ceph-Cluster via ${HOST_SHORT}"

run_capture "osd-dump" "ceph osd dump | egrep 'flags|noout|norecover|nobackfill|noscrub|nodeep-scrub'" ceph osd dump
if run_ready "$SCOPE" "$CATEGORY" "Flags" "ceph osd dump | egrep 'flags|noout|norecover|nobackfill|noscrub|nodeep-scrub'"; then
    flags="$(awk '/^flags[[:space:]]/ {sub(/^flags[[:space:]]+/,""); print; exit}' "$RUN_STDOUT")"
    emit_record "$SCOPE" "$CATEGORY" "OSD Flags / Active" "${flags:-none reported}" "ceph osd dump | egrep 'flags|noout|norecover|nobackfill|noscrub|nodeep-scrub'" "$RUN_TS" "Pool flags intentionally excluded from normalized result; Evidence=${RUN_EVIDENCE_REL}"
    for flag in noout norecover nobackfill noscrub nodeep-scrub; do
        state="N"; [[ ",${flags}," == *",${flag},"* ]] && state="Y"
        emit_record "$SCOPE" "$CATEGORY" "Protection Flag / $flag" "$state" "ceph osd dump | egrep 'flags|noout|norecover|nobackfill|noscrub|nodeep-scrub'" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

run_capture "config-dump" "ceph config dump" ceph config dump
if run_ready "$SCOPE" "$CATEGORY" "Scrub/Recovery Config" "ceph config dump"; then
    scrub_count=0
    while IFS=$'\t' read -r option value; do scrub_count=$((scrub_count+1)); emit_record "$SCOPE" "$CATEGORY" "Scrub Setting / $option" "$value" "ceph config dump | egrep 'osd_scrub|deep_scrub' | head -n 50" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done < <(awk '{for(i=1;i<=NF;i++) if($i ~ /osd_scrub|deep_scrub/){print $i "\t" $(i+1); break}}' "$RUN_STDOUT" | head -n 50)
    [[ $scrub_count -gt 0 ]] || emit_status "$SCOPE" "$CATEGORY" "Scrub Settings" "NO_EXPLICIT_OVERRIDE" "ceph config dump | egrep 'osd_scrub|deep_scrub' | head -n 50" "$RUN_TS" "No matching explicit config-db overrides found; this is not treated as a command failure; Evidence=${RUN_EVIDENCE_REL}"
    rec_count=0
    while IFS=$'\t' read -r option value; do rec_count=$((rec_count+1)); emit_record "$SCOPE" "$CATEGORY" "Recovery Setting / $option" "$value" "ceph config dump | egrep 'osd_recovery|osd_max_backfills|osd_recovery_max_active' | head -n 50" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done < <(awk '{for(i=1;i<=NF;i++) if($i ~ /osd_recovery|osd_max_backfills|osd_recovery_max_active/){print $i "\t" $(i+1); break}}' "$RUN_STDOUT" | head -n 50)
    [[ $rec_count -gt 0 ]] || emit_status "$SCOPE" "$CATEGORY" "Backfill/Recovery" "NO_EXPLICIT_OVERRIDE" "ceph config dump | egrep 'osd_recovery|osd_max_backfills|osd_recovery_max_active' | head -n 50" "$RUN_TS" "No matching explicit config-db overrides found; this is not treated as a command failure; Evidence=${RUN_EVIDENCE_REL}"
fi
finish_collector
