#!/usr/bin/env bash
# AP1 2.3 - HA / Ressourcenverwaltung
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "ProxMox_Cluster" "03" "ProxMoxCluster" "PVEHA"
CATEGORY="HA / Ressourcenverwaltung"
SCOPE="PVE-Cluster via ${HOST_SHORT}"

run_capture "ha-status" "ha-manager status" ha-manager status
if run_ready "$SCOPE" "$CATEGORY" "HA Status" "ha-manager status"; then
    awk 'NF {key=$1; $1=""; sub(/^[[:space:]]+/,"",$0); c[key]++; print key " " c[key] "\t" $0}' "$RUN_STDOUT" |
    while IFS=$'\t' read -r param value; do emit_record "$SCOPE" "$CATEGORY" "HA Status / $param" "$value" "ha-manager status" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "ha-config" "ha-manager config" ha-manager config
if [[ $RUN_RC -ne 0 ]]; then run_ready "$SCOPE" "$CATEGORY" "HA Ressourcen" "ha-manager config" || true
elif [[ ! -s "$RUN_STDOUT" ]]; then emit_no_data "$SCOPE" "$CATEGORY" "HA Ressourcen" "ha-manager config" "$RUN_TS" "No HA resources configured"
else
    awk 'NF {print "Entry " ++n "\t" $0}' "$RUN_STDOUT" | while IFS=$'\t' read -r p v; do emit_record "$SCOPE" "$CATEGORY" "HA Ressourcen / $p" "$v" "ha-manager config" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "qm-list" "qm list" qm list
if run_ready "$SCOPE" "$CATEGORY" "VM Inventory" "qm list"; then
    awk 'NR>1 && $1~/^[0-9]+$/ {id=$1; print id "\tName\t" $2; print id "\tStatus\t" $3; print id "\tMemory MB\t" $4; print id "\tBootdisk GB\t" $5; print id "\tPID\t" $6}' "$RUN_STDOUT" |
    while IFS=$'\t' read -r id field value; do emit_record "VMID $id" "$CATEGORY" "VM / $field" "$value" "qm list" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "pct-list" "pct list" pct list
if run_ready "$SCOPE" "$CATEGORY" "CT Inventory" "pct list"; then
    awk 'NR>1 && $1~/^[0-9]+$/ {id=$1; status=$2; if(NF>=4){lock=$3; name=$4}else{lock=""; name=$3} print id "\tStatus\t" status; print id "\tLock\t" lock; print id "\tName\t" name}' "$RUN_STDOUT" |
    while IFS=$'\t' read -r id field value; do emit_record "CTID $id" "$CATEGORY" "CT / $field" "$value" "pct list" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "cluster-resources-json" "pvesh get /cluster/resources --type vm --output-format json" pvesh get /cluster/resources --type vm --output-format json
if run_ready "$SCOPE" "$CATEGORY" "VM Details (API)" "pvesh get /cluster/resources --type vm --output-format json"; then
    json_array_fields "$RUN_STDOUT" . id type node status vmid name cpu maxcpu mem maxmem disk maxdisk uptime template tags hastate | while IFS=$'\t' read -r entity field value; do
        emit_record "$entity" "$CATEGORY" "Resource / $field" "$value" "pvesh get /cluster/resources --type vm" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

# PVE 9+: HA groups were replaced by HA rules. Prefer the current rules CLI.
run_capture "ha-rules-json" "ha-manager rules list --output-format json" ha-manager rules list --output-format json
if [[ $RUN_RC -eq 0 ]]; then
    if [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then
        emit_no_data "$SCOPE" "$CATEGORY" "HA Rules" "ha-manager rules list --output-format json" "$RUN_TS" "No HA rules returned"
    else
        json_array_fields "$RUN_STDOUT" . rule type enabled state resources nodes strict affinity disable comment errors | while IFS=$'\t' read -r rule field value; do
            emit_record "HA Rule $rule" "$CATEGORY" "HA Rule / $field" "$value" "ha-manager rules list" "$RUN_TS" "PVE 9+ HA rules; Read-only; Evidence=${RUN_EVIDENCE_REL}"
        done
    fi
else
    # Compatibility fallback for PVE releases where 'ha-manager rules' is not available yet.
    RULES_RC=$RUN_RC
    RULES_TS=$RUN_TS
    RULES_EVIDENCE=$RUN_EVIDENCE_REL
    run_capture "ha-groups-legacy-json" "pvesh get /cluster/ha/groups --output-format json" pvesh get /cluster/ha/groups --output-format json
    if [[ $RUN_RC -eq 0 ]]; then
        emit_status "$SCOPE" "$CATEGORY" "HA Rules" "LEGACY_GROUPS" "pvesh get /cluster/ha/groups --output-format json" "$RUN_TS" "Current HA rules CLI unavailable (ExitCode=${RULES_RC}); using legacy read-only HA groups for pre-PVE-9 compatibility; RulesEvidence=${RULES_EVIDENCE}; Evidence=${RUN_EVIDENCE_REL}"
        if [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then
            emit_no_data "$SCOPE" "$CATEGORY" "HA Gruppen (Legacy)" "pvesh get /cluster/ha/groups --output-format json" "$RUN_TS" "No legacy HA groups returned"
        else
            json_array_fields "$RUN_STDOUT" . group nodes nofailback restricted comment | while IFS=$'\t' read -r group field value; do
                emit_record "HA Group $group" "$CATEGORY" "HA Group (Legacy) / $field" "$value" "pvesh get /cluster/ha/groups" "$RUN_TS" "Pre-PVE-9 compatibility; Read-only; Evidence=${RUN_EVIDENCE_REL}"
            done
        fi
    else
        err="$(head -n 3 "$RUN_STDERR" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
        emit_status "$SCOPE" "$CATEGORY" "HA Rules" "ERROR" "ha-manager rules list --output-format json" "$RULES_TS" "Rules ExitCode=${RULES_RC}; legacy fallback ExitCode=${RUN_RC}; ${err:-both HA rule/group queries failed}; RulesEvidence=${RULES_EVIDENCE}; LegacyEvidence=${RUN_EVIDENCE_REL}"
    fi
fi
finish_collector
