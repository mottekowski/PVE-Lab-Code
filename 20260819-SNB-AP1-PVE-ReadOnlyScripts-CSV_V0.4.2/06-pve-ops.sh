#!/usr/bin/env bash
# AP1 2.6 - Auth, Logging, Monitoring, Backup
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "ProxMox_Cluster" "06" "ProxMoxCluster" "PVEOps"
CATEGORY="Auth / Logging / Monitoring / Backup"
SCOPE="PVE-Cluster via ${HOST_SHORT}"

run_capture "access-domains-json" "pvesh get /access/domains --output-format json" pvesh get /access/domains --output-format json
if run_ready "$SCOPE" "$CATEGORY" "User/Realm - Domains" "pvesh get /access/domains --output-format json"; then
    json_array_fields "$RUN_STDOUT" . realm type comment tfa default | while IFS=$'\t' read -r realm field value; do emit_record "Realm $realm" "$CATEGORY" "Realm / $field" "$value" "pvesh get /access/domains" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "access-users-json" "pvesh get /access/users --output-format json" pvesh get /access/users --output-format json
if run_ready "$SCOPE" "$CATEGORY" "User/Realm - Users" "pvesh get /access/users --output-format json"; then
    json_array_fields "$RUN_STDOUT" . userid enable expire groups realm-type tokens | while IFS=$'\t' read -r user field value; do emit_record "User $user" "$CATEGORY" "User / $field" "$value" "pvesh get /access/users" "$RUN_TS" "Read-only; PII fields intentionally not exported; Evidence=${RUN_EVIDENCE_REL}"; done
fi

# --limit 50 remains excluded because it is red-marked in the source document.
run_capture "cluster-tasks-json" "pvesh get /cluster/tasks --output-format json" pvesh get /cluster/tasks --output-format json
if run_ready "$SCOPE" "$CATEGORY" "Task Log" "pvesh get /cluster/tasks --output-format json"; then
    count="$(perl -MJSON::PP -0777 -e '$d=decode_json(<>); print ref($d) eq "ARRAY" ? scalar(@$d) : 0' < "$RUN_STDOUT")"
    emit_record "$SCOPE" "$CATEGORY" "Tasks / Returned count" "$count" "pvesh get /cluster/tasks" "$RUN_TS" "Read-only; normalized details capped to first 20 returned tasks; Evidence=${RUN_EVIDENCE_REL}"
    json_array_fields "$RUN_STDOUT" . upid type id node user starttime endtime status | head -n 140 | while IFS=$'\t' read -r task field value; do emit_record "$SCOPE" "$CATEGORY" "Task / $task / $field" "$value" "pvesh get /cluster/tasks" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture_shell "critical-journal" "journalctl -p 3 -xb --no-pager | head -n 200" 'set +o pipefail; journalctl -p 3 -xb --no-pager | head -n 200'
if [[ $RUN_RC -ne 0 ]]; then run_ready "$HOST_SHORT" "$CATEGORY" "System Logs" "journalctl -p 3 -xb --no-pager | head -n 200" || true
elif [[ ! -s "$RUN_STDOUT" ]]; then emit_no_data "$HOST_SHORT" "$CATEGORY" "System Logs" "journalctl -p 3 -xb --no-pager | head -n 200" "$RUN_TS" "No priority-3 boot log lines returned"
else
    lines="$(wc -l < "$RUN_STDOUT" | tr -d ' ')"; emit_record "$HOST_SHORT" "$CATEGORY" "System Logs / Critical line count" "$lines" "journalctl -p 3 -xb --no-pager | head -n 200" "$RUN_TS" "Read-only; full messages in Evidence=${RUN_EVIDENCE_REL}"
    awk 'NF>=5 {proc=$5; sub(/\[[0-9]+\]:?$/,"",proc); sub(/:$/,"",proc); c[proc]++} END{for(p in c) print p "\t" c[p]}' "$RUN_STDOUT" | sort -k2,2nr |
    while IFS=$'\t' read -r proc n; do emit_record "$HOST_SHORT" "$CATEGORY" "System Logs / Source count / $proc" "$n" "journalctl -p 3 -xb --no-pager | head -n 200" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "cluster-backup-json" "pvesh get /cluster/backup --output-format json" pvesh get /cluster/backup --output-format json
if [[ $RUN_RC -ne 0 ]]; then run_ready "$SCOPE" "$CATEGORY" "Backup Jobs" "pvesh get /cluster/backup --output-format json" || true
elif [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then emit_no_data "$SCOPE" "$CATEGORY" "Backup Jobs" "pvesh get /cluster/backup --output-format json" "$RUN_TS" "No vzdump jobs configured"
else
    json_flatten "$RUN_STDOUT" . | while IFS=$'\t' read -r path value; do emit_record "$SCOPE" "$CATEGORY" "Backup Jobs / $path" "$value" "pvesh get /cluster/backup" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "pvesm-status" "pvesm status | grep -i pbs" pvesm status
if run_ready "$SCOPE" "$CATEGORY" "PBS Storage" "pvesm status | grep -i pbs"; then
    matched=0
    while read -r name type status total used avail pct; do
        [[ "$type" == "pbs" || "$name" =~ [Pp][Bb][Ss] ]] || continue; matched=1
        emit_record "Storage $name" "$CATEGORY" "PBS Storage / Type" "$type" "pvesm status | grep -i pbs" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        emit_record "Storage $name" "$CATEGORY" "PBS Storage / Status" "$status" "pvesm status | grep -i pbs" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        emit_record "Storage $name" "$CATEGORY" "PBS Storage / Used Percent" "$pct" "pvesm status | grep -i pbs" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done < <(awk 'NR>1 && NF>=7 {print $1,$2,$3,$4,$5,$6,$7}' "$RUN_STDOUT")
    [[ $matched -eq 1 ]] || emit_no_data "$SCOPE" "$CATEGORY" "PBS Storage" "pvesm status | grep -i pbs" "$RUN_TS" "No PBS storage found"
fi
finish_collector
