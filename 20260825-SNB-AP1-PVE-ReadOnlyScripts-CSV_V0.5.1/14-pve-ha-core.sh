#!/usr/bin/env bash
# AP1 V0.5 extension - HA Architecture Critical / CORE.
# Read-only, non-invasive. No migration, relocation, fencing, maintenance or state change is performed.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "ProxMox_Cluster" "14" "ProxMoxCluster" "PVEHACore"

SCOPE="PVE-Cluster via ${HOST_SHORT}"
TS="$(date --iso-8601=seconds)"
emit_record "$SCOPE" "HA / Architecture Critical" "Classification" "ARCHITECTURE_CRITICAL / CORE" "AP1 V0.5 scope" "$TS" "Facts only; no target architecture calculated"

# HA runtime status. This contains quorum/master/LRM/service rows and provides current node/requested state correlation.
run_capture "ha-status-current-json" "pvesh get /cluster/ha/status/current --output-format json" pvesh get /cluster/ha/status/current --output-format json
HA_STATUS_FILE="${TMP_ROOT}/ha-status-current.saved.json"
if [[ $RUN_RC -ne 0 ]]; then
    run_ready "$SCOPE" "HA / Status" "HA Manager Current Status" "pvesh get /cluster/ha/status/current --output-format json" || true
    : > "$HA_STATUS_FILE"
elif [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then
    emit_no_data "$SCOPE" "HA / Status" "HA Manager Current Status" "pvesh get /cluster/ha/status/current --output-format json" "$RUN_TS" "No HA status entries returned"
    : > "$HA_STATUS_FILE"
else
    cp "$RUN_STDOUT" "$HA_STATUS_FILE"
    json_array_fields "$RUN_STDOUT" . id type node status quorate sid state crm_state request_state max_restart max_relocate failback timestamp | \
    while IFS=$'\t' read -r id field value; do
        emit_record "HA Status $id" "HA / Status" "HA Status / $field" "$value" "pvesh get /cluster/ha/status/current" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

# Full manager/LRM object for architecture-critical failure-state analysis.
run_capture "ha-manager-status-json" "pvesh get /cluster/ha/status/manager_status --output-format json" pvesh get /cluster/ha/status/manager_status --output-format json
if [[ $RUN_RC -ne 0 ]]; then
    run_ready "$SCOPE" "HA / Manager-LRM" "Manager/LRM Status" "pvesh get /cluster/ha/status/manager_status --output-format json" || true
elif [[ ! -s "$RUN_STDOUT" || "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "{}" ]]; then
    emit_no_data "$SCOPE" "HA / Manager-LRM" "Manager/LRM Status" "pvesh get /cluster/ha/status/manager_status --output-format json" "$RUN_TS" "No manager/LRM status returned"
else
    json_flatten "$RUN_STDOUT" . | while IFS=$'\t' read -r path value; do
        emit_record "$SCOPE" "HA / Manager-LRM" "Manager Status / $path" "$value" "pvesh get /cluster/ha/status/manager_status" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

# HA resources. Filter output to stretch-relevant fields and deliberately exclude free-form comments/digests.
run_capture_shell "ha-resources-safe-json" \
  "pvesh get /cluster/ha/resources --output-format json (stretch-relevant fields only)" \
  "pvesh get /cluster/ha/resources --output-format json | perl -MJSON::PP -0777 -e 'my \$d=decode_json(<>); my @o; for my \$r (@{\$d||[]}) { next unless ref(\$r) eq q{HASH}; my %x; for my \$k (qw(sid type state group max_restart max_relocate failback auto-rebalance)) { \$x{\$k}=\$r->{\$k} if exists \$r->{\$k}; } push @o, \\%x if defined \$x{sid}; } print encode_json(\\@o);'"
HA_RES_FILE="${TMP_ROOT}/ha-resources.saved.json"
if [[ $RUN_RC -ne 0 ]]; then
    run_ready "$SCOPE" "HA / Resources" "HA Resources" "pvesh get /cluster/ha/resources --output-format json" || true
    printf '[]' > "$HA_RES_FILE"
elif [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then
    printf '[]' > "$HA_RES_FILE"
    emit_status "$SCOPE" "HA / Resources" "HA Resources" "NO_HA_RESOURCES_CONFIGURED" "pvesh get /cluster/ha/resources" "$RUN_TS" "Valid analysis result; Evidence=${RUN_EVIDENCE_REL}"
    emit_record "$SCOPE" "HA / Resources" "HA Resources / Count" "0" "pvesh get /cluster/ha/resources" "$RUN_TS" "Read-only"
else
    cp "$RUN_STDOUT" "$HA_RES_FILE"
    resource_count="$(perl -MJSON::PP -0777 -e 'my $d=decode_json(<>); print ref($d) eq "ARRAY" ? scalar(@$d) : 0' < "$HA_RES_FILE")"
    emit_record "$SCOPE" "HA / Resources" "HA Resources / Count" "$resource_count" "pvesh get /cluster/ha/resources" "$RUN_TS" "Evidence=${RUN_EVIDENCE_REL}"
    json_array_fields "$HA_RES_FILE" . sid type state group max_restart max_relocate failback auto-rebalance | while IFS=$'\t' read -r sid field value; do
        label="$field"
        [[ "$field" == "state" ]] && label="requested_state"
        emit_record "HA Resource $sid" "HA / Resources" "HA Resource / $label" "$value" "pvesh get /cluster/ha/resources" "$RUN_TS" "Read-only; correlate by SID/VMID; Evidence=${RUN_EVIDENCE_REL}"
    done
fi

# PVE 9+: HA rules. Enumerate rule IDs and query each rule detail. Legacy groups are a fallback for older PVE.
run_capture_shell "ha-rules-list-json" \
  "ha-manager rules list --output-format json (rule/type only; comments excluded)" \
  "ha-manager rules list --output-format json | perl -MJSON::PP -0777 -e 'my \$d=decode_json(<>); my @o; for my \$r (@{\$d||[]}) { next unless ref(\$r) eq q{HASH} && defined \$r->{rule}; push @o, { rule=>\$r->{rule}, type=>(\$r->{type}//q{}) }; } print encode_json(\\@o);'"
if [[ $RUN_RC -eq 0 ]]; then
    if [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then
        emit_status "$SCOPE" "HA / Placement Rules" "HA Rules" "NO_HA_RULES_CONFIGURED" "ha-manager rules list --output-format json" "$RUN_TS" "Valid analysis result; Evidence=${RUN_EVIDENCE_REL}"
    else
        mapfile -t RULE_IDS < <(perl -MJSON::PP -0777 -e 'my $d=decode_json(<>); for my $r (@{$d||[]}) { print "$r->{rule}\n" if ref($r) eq "HASH" && defined $r->{rule}; }' < "$RUN_STDOUT")
        for rule in "${RULE_IDS[@]}"; do
            [[ -n "$rule" ]] || continue
            printf -v rule_q '%q' "$rule"
            run_capture_shell "ha-rule-${rule//[^A-Za-z0-9._-]/_}-safe" \
              "pvesh get /cluster/ha/rules/${rule} --output-format json (stretch-relevant fields only)" \
              "pvesh get /cluster/ha/rules/${rule_q} --output-format json | perl -MJSON::PP -0777 -e 'my \$r=decode_json(<>); my %x; for my \$k (qw(rule type enabled state resources nodes strict affinity disable order priority)) { \$x{\$k}=\$r->{\$k} if ref(\$r) eq q{HASH} && exists \$r->{\$k}; } print encode_json(\\%x);'"
            if [[ $RUN_RC -ne 0 ]]; then
                err="$(head -n 2 "$RUN_STDERR" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
                emit_status "HA Rule $rule" "HA / Placement Rules" "Rule Detail" "UNAVAILABLE" "pvesh get /cluster/ha/rules/${rule}" "$RUN_TS" "ExitCode=${RUN_RC}; ${err:-rule detail unavailable}; Evidence=${RUN_EVIDENCE_REL}"
                continue
            fi
            json_object_fields "$RUN_STDOUT" rule type enabled state resources nodes strict affinity disable order priority | while IFS=$'\t' read -r field value; do
                emit_record "HA Rule $rule" "HA / Placement Rules" "HA Rule / $field" "$value" "pvesh get /cluster/ha/rules/${rule}" "$RUN_TS" "PVE 9+; Read-only; Evidence=${RUN_EVIDENCE_REL}"
            done
        done
    fi
else
    rules_rc=$RUN_RC
    rules_evidence=$RUN_EVIDENCE_REL
    run_capture_shell "ha-groups-legacy-safe-json" \
      "pvesh get /cluster/ha/groups --output-format json (legacy placement fields only)" \
      "pvesh get /cluster/ha/groups --output-format json | perl -MJSON::PP -0777 -e 'my \$d=decode_json(<>); my @o; for my \$g (@{\$d||[]}) { next unless ref(\$g) eq q{HASH}; my %x; for my \$k (qw(group nodes nofailback restricted)) { \$x{\$k}=\$g->{\$k} if exists \$g->{\$k}; } push @o, \\%x if defined \$x{group}; } print encode_json(\\@o);'"
    if [[ $RUN_RC -eq 0 ]]; then
        emit_status "$SCOPE" "HA / Placement Rules" "HA Rules" "FEATURE_NOT_AVAILABLE_IN_PVE_VERSION" "ha-manager rules list --output-format json" "$RUN_TS" "Using legacy HA Groups compatibility path; RulesExitCode=${rules_rc}; RulesEvidence=${rules_evidence}; GroupsEvidence=${RUN_EVIDENCE_REL}"
        if [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then
            emit_status "$SCOPE" "HA / Placement Rules" "Legacy HA Groups" "NO_HA_GROUPS_CONFIGURED" "pvesh get /cluster/ha/groups" "$RUN_TS" "Valid analysis result; Evidence=${RUN_EVIDENCE_REL}"
        else
            json_array_fields "$RUN_STDOUT" . group nodes nofailback restricted | while IFS=$'\t' read -r group field value; do
                emit_record "HA Group $group" "HA / Placement Rules" "HA Group (Legacy) / $field" "$value" "pvesh get /cluster/ha/groups" "$RUN_TS" "Pre-PVE-9 compatibility; Read-only; Evidence=${RUN_EVIDENCE_REL}"
            done
        fi
    else
        emit_status "$SCOPE" "HA / Placement Rules" "HA Placement Feature" "FEATURE_NOT_AVAILABLE_OR_ACCESS_RESTRICTED" "ha-manager rules list / pvesh get /cluster/ha/groups" "$(date --iso-8601=seconds)" "Neither current rules nor legacy groups could be read; review Evidence"
    fi
fi

# Correlate complete VM/CT inventory with HA-managed Yes/No via VMID/CTID without duplicating full guest configuration.
run_capture_shell "cluster-resources-ha-correlation-safe-json" \
  "pvesh get /cluster/resources --type vm --output-format json (correlation fields only)" \
  "pvesh get /cluster/resources --type vm --output-format json | perl -MJSON::PP -0777 -e 'my \$d=decode_json(<>); my @o; for my \$r (@{\$d||[]}) { next unless ref(\$r) eq q{HASH}; my %x; for my \$k (qw(id type node status vmid)) { \$x{\$k}=\$r->{\$k} if exists \$r->{\$k}; } push @o, \\%x if defined \$x{vmid}; } print encode_json(\\@o);'"
if [[ $RUN_RC -ne 0 ]]; then
    run_ready "$SCOPE" "HA / Workload Correlation" "VM/CT Correlation" "pvesh get /cluster/resources --type vm" || true
elif [[ ! -s "$RUN_STDOUT" || "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" ]]; then
    emit_no_data "$SCOPE" "HA / Workload Correlation" "VM/CT Correlation" "pvesh get /cluster/resources --type vm" "$RUN_TS" "No VM/CT resources returned"
else
    CORR_RES_FILE="${TMP_ROOT}/cluster-resources.correlation.json"
    cp "$RUN_STDOUT" "$CORR_RES_FILE"
    perl -MJSON::PP -0777 -e '
        my ($guestf,$haf,$statusf)=@ARGV;
        sub readj { my($f,$default)=@_; return $default unless -s $f; open my $h,"<",$f or return $default; local $/; my $t=<$h>; close $h; eval { decode_json($t) } // $default; }
        my $g=readj($guestf,[]); my $h=readj($haf,[]); my $s=readj($statusf,[]);
        my %ha=map { (($_->{sid}//"") => $_) } grep { ref($_) eq "HASH" && defined $_->{sid} } @$h;
        my %rt=map { (($_->{sid}//"") => $_) } grep { ref($_) eq "HASH" && ($_->{type}//"") eq "service" && defined $_->{sid} } @$s;
        for my $r (@$g) {
            next unless ref($r) eq "HASH" && defined $r->{vmid};
            my $kind=$r->{type}//""; my $sid = $kind eq "lxc" ? "ct:$r->{vmid}" : "vm:$r->{vmid}";
            my $managed=exists($ha{$sid}) ? "Yes" : "No";
            my $node=$r->{node}//""; my $status=$r->{status}//"";
            my $runtime_node=exists($rt{$sid}) ? ($rt{$sid}->{node}//"") : "";
            my $runtime_state=exists($rt{$sid}) ? ($rt{$sid}->{state}//$rt{$sid}->{status}//"") : "";
            print join("\t",$sid,$managed,$node,$status,$runtime_node,$runtime_state),"\n";
        }
    ' "$CORR_RES_FILE" "$HA_RES_FILE" "$HA_STATUS_FILE" | while IFS=$'\t' read -r sid managed current_node guest_status runtime_node runtime_state; do
        emit_record "Workload $sid" "HA / Workload Correlation" "HA Correlation / HA Managed" "$managed" "cluster resources + HA resources" "$RUN_TS" "Correlation by VMID/CTID; no guest config duplication"
        emit_record "Workload $sid" "HA / Workload Correlation" "HA Correlation / Current Node" "$current_node" "pvesh get /cluster/resources --type vm" "$RUN_TS" "Correlation by VMID/CTID"
        emit_record "Workload $sid" "HA / Workload Correlation" "HA Correlation / Guest Status" "$guest_status" "pvesh get /cluster/resources --type vm" "$RUN_TS" "Correlation by VMID/CTID"
        [[ -n "$runtime_node" ]] && emit_record "Workload $sid" "HA / Workload Correlation" "HA Correlation / HA Runtime Node" "$runtime_node" "pvesh get /cluster/ha/status/current" "$RUN_TS" "Only for HA-managed workload"
        [[ -n "$runtime_state" ]] && emit_record "Workload $sid" "HA / Workload Correlation" "HA Correlation / HA Runtime State" "$runtime_state" "pvesh get /cluster/ha/status/current" "$RUN_TS" "Only for HA-managed workload"
    done
fi

finish_collector
