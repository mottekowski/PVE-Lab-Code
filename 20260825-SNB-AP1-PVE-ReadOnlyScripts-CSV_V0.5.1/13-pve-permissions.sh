#!/usr/bin/env bash
# AP1 V0.5 extension - Permissions / Roles / Groups / ACLs / API token metadata.
# Read-only, non-invasive. Does not read token secrets, passwords, private keys or recovery keys.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "ProxMox_Cluster" "13" "ProxMoxCluster" "PVEPermissions"

SCOPE="PVE-Cluster via ${HOST_SHORT}"
emit_record "$SCOPE" "Permissions / Overview" "Classification" "CORE" "AP1 V0.5 scope" "$(date --iso-8601=seconds)" "Read-only technical baseline; no security/compliance rating"
emit_record "$SCOPE" "Permissions / Overview" "Sensitive Data Policy" "NO_SECRETS_EXPORTED" "AP1 V0.5 collector policy" "$(date --iso-8601=seconds)" "Token secrets, passwords, bind passwords, private keys, API secrets and recovery keys are explicitly excluded"

# Roles: roleid, privileges and the API-provided 'special' flag (built-in role indicator).
run_capture "access-roles-json" "pvesh get /access/roles --output-format json" pvesh get /access/roles --output-format json
if [[ $RUN_RC -ne 0 ]]; then
    run_ready "$SCOPE" "Permissions / Roles" "Roles" "pvesh get /access/roles --output-format json" || true
elif [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then
    emit_no_data "$SCOPE" "Permissions / Roles" "Roles" "pvesh get /access/roles --output-format json" "$RUN_TS" "No roles returned"
else
    perl -MJSON::PP -0777 -e '
        my $d=decode_json(<>); exit 0 unless ref($d) eq "ARRAY";
        for my $r (@$d) {
            next unless ref($r) eq "HASH" && defined $r->{roleid};
            my $special = exists($r->{special}) ? $r->{special} : "";
            my $type = $special eq "1" ? "BUILT_IN" : ($special eq "0" ? "CUSTOM" : "UNKNOWN");
            my $privs = defined($r->{privs}) ? $r->{privs} : "";
            $privs =~ s/[\r\n\t]+/ /g;
            print join("\t", $r->{roleid}, $type, $privs), "\n";
        }
    ' < "$RUN_STDOUT" | while IFS=$'\t' read -r roleid roletype privs; do
        emit_record "Role $roleid" "Permissions / Roles" "Role / ID" "$roleid" "pvesh get /access/roles" "$RUN_TS" "Evidence=${RUN_EVIDENCE_REL}"
        emit_record "Role $roleid" "Permissions / Roles" "Role / Type" "$roletype" "pvesh get /access/roles" "$RUN_TS" "Built-in classification uses API field special; Evidence=${RUN_EVIDENCE_REL}"
        [[ -n "$privs" ]] && emit_record "Role $roleid" "Permissions / Roles" "Role / Privileges" "$privs" "pvesh get /access/roles" "$RUN_TS" "Evidence=${RUN_EVIDENCE_REL}"
    done
fi

# Groups: list group IDs and retrieve only members. Comments are intentionally excluded before Evidence is written.
run_capture_shell "access-groups-json" \
  "pvesh get /access/groups --output-format json (groupid only; comments excluded)" \
  "pvesh get /access/groups --output-format json | perl -MJSON::PP -0777 -e 'my \$d=decode_json(<>); my @o; for my \$g (@{\$d||[]}) { next unless ref(\$g) eq q{HASH} && defined \$g->{groupid}; push @o, { groupid=>\$g->{groupid} }; } print encode_json(\\@o);'"
if [[ $RUN_RC -ne 0 ]]; then
    run_ready "$SCOPE" "Permissions / Groups" "Groups" "pvesh get /access/groups --output-format json" || true
elif [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then
    emit_no_data "$SCOPE" "Permissions / Groups" "Groups" "pvesh get /access/groups --output-format json" "$RUN_TS" "No groups returned"
else
    mapfile -t GROUP_IDS < <(perl -MJSON::PP -0777 -e 'my $d=decode_json(<>); for my $g (@{$d||[]}) { print "$g->{groupid}\n" if ref($g) eq "HASH" && defined $g->{groupid}; }' < "$RUN_STDOUT")
    for groupid in "${GROUP_IDS[@]}"; do
        [[ -n "$groupid" ]] || continue
        emit_record "Group $groupid" "Permissions / Groups" "Group / ID" "$groupid" "pvesh get /access/groups" "$RUN_TS" "Evidence=${RUN_EVIDENCE_REL}"
        printf -v group_q '%q' "$groupid"
        run_capture_shell "group-${groupid//[^A-Za-z0-9._-]/_}-members" \
          "pvesh get /access/groups/${groupid} --output-format json (members only; comments excluded)" \
          "pvesh get /access/groups/${group_q} --output-format json | perl -MJSON::PP -0777 -e 'my \$d=decode_json(<>); my \$m=\$d->{members}||[]; print scalar(@\$m), qq{\\n}; print qq{\$_\\n} for @\$m;'"
        if [[ $RUN_RC -ne 0 ]]; then
            err="$(head -n 2 "$RUN_STDERR" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
            emit_status "Group $groupid" "Permissions / Groups" "Group Members" "UNAVAILABLE" "pvesh get /access/groups/${groupid}" "$RUN_TS" "ExitCode=${RUN_RC}; ${err:-group details unavailable}; Evidence=${RUN_EVIDENCE_REL}"
            continue
        fi
        member_count="$(head -n1 "$RUN_STDOUT" | tr -d '[:space:]')"
        emit_record "Group $groupid" "Permissions / Groups" "Group / Member Count" "${member_count:-0}" "pvesh get /access/groups/${groupid}" "$RUN_TS" "Comments excluded; Evidence=${RUN_EVIDENCE_REL}"
        tail -n +2 "$RUN_STDOUT" | while IFS= read -r member; do
            [[ -n "$member" ]] || continue
            emit_record "Group $groupid" "Permissions / Groups" "Group / Member" "$member" "pvesh get /access/groups/${groupid}" "$RUN_TS" "Identity linkage required for permission mapping; Evidence=${RUN_EVIDENCE_REL}"
        done
    done
fi

# ACLs: one technical ACL tuple, normalized into atomic rows.
run_capture "access-acl-json" "pvesh get /access/acl --output-format json" pvesh get /access/acl --output-format json
if [[ $RUN_RC -ne 0 ]]; then
    run_ready "$SCOPE" "Permissions / ACLs" "ACLs" "pvesh get /access/acl --output-format json" || true
elif [[ "$(tr -d '[:space:]' < "$RUN_STDOUT")" == "[]" || ! -s "$RUN_STDOUT" ]]; then
    emit_no_data "$SCOPE" "Permissions / ACLs" "ACLs" "pvesh get /access/acl --output-format json" "$RUN_TS" "No ACL entries returned"
else
    perl -MJSON::PP -0777 -e '
        my $d=decode_json(<>); exit 0 unless ref($d) eq "ARRAY";
        my $i=0;
        for my $a (@$d) {
            next unless ref($a) eq "HASH";
            $i++;
            my $ugid=$a->{ugid}//""; my $type=$a->{type}//"unknown";
            my $realm="N/A";
            if (($type eq "user" || $type eq "token") && $ugid =~ /\@([^!]+)(?:!|$)/) { $realm=$1; }
            my @v=($i,$ugid,$type,$realm,$a->{roleid}//"",$a->{path}//"",defined($a->{propagate})?$a->{propagate}:"");
            for (@v) { $_="" if !defined $_; s/[\r\n\t]+/ /g; }
            print join("\t",@v),"\n";
        }
    ' < "$RUN_STDOUT" | while IFS=$'\t' read -r idx principal ptype realm role path propagate; do
        aclscope="ACL ${idx} / ${principal:-unknown}"
        emit_record "$aclscope" "Permissions / ACLs" "ACL / Principal" "$principal" "pvesh get /access/acl" "$RUN_TS" "Evidence=${RUN_EVIDENCE_REL}"
        emit_record "$aclscope" "Permissions / ACLs" "ACL / Principal Type" "$ptype" "pvesh get /access/acl" "$RUN_TS" "Evidence=${RUN_EVIDENCE_REL}"
        emit_record "$aclscope" "Permissions / ACLs" "ACL / Realm" "$realm" "pvesh get /access/acl" "$RUN_TS" "Derived from principal ID for user/token; Evidence=${RUN_EVIDENCE_REL}"
        emit_record "$aclscope" "Permissions / ACLs" "ACL / Role" "$role" "pvesh get /access/acl" "$RUN_TS" "Evidence=${RUN_EVIDENCE_REL}"
        emit_record "$aclscope" "Permissions / ACLs" "ACL / Path" "$path" "pvesh get /access/acl" "$RUN_TS" "Evidence=${RUN_EVIDENCE_REL}"
        emit_record "$aclscope" "Permissions / ACLs" "ACL / Propagate" "$propagate" "pvesh get /access/acl" "$RUN_TS" "Evidence=${RUN_EVIDENCE_REL}"
    done
fi

# API token metadata. Enumerate only userid first, then filter token list to safe metadata.
# No token secret can be returned by the list command; comments are additionally discarded.
run_capture_shell "access-userids" \
  "pvesh get /access/users --output-format json (userid only; PII fields excluded)" \
  "pvesh get /access/users --output-format json | perl -MJSON::PP -0777 -e 'my \$d=decode_json(<>); for my \$u (@{\$d||[]}) { print qq{\$u->{userid}\\n} if ref(\$u) eq q{HASH} && defined \$u->{userid}; }'"
if [[ $RUN_RC -ne 0 ]]; then
    err="$(head -n 2 "$RUN_STDERR" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
    emit_status "$SCOPE" "Permissions / API Tokens" "Token Metadata" "UNAVAILABLE" "pvesh get /access/users (userid only)" "$RUN_TS" "ExitCode=${RUN_RC}; ${err:-user enumeration unavailable}; Evidence=${RUN_EVIDENCE_REL}"
else
    USERID_FILE="${TMP_ROOT}/userids.safe.txt"
    cp "$RUN_STDOUT" "$USERID_FILE"
    token_total=0
    token_failures=0
    while IFS= read -r userid; do
        [[ -n "$userid" ]] || continue
        printf -v user_q '%q' "$userid"
        token_slug="token-${userid//[^A-Za-z0-9._-]/_}"
        run_capture_shell "$token_slug" \
          "pveum user token list ${userid} --output-format json (safe metadata only)" \
          "pveum user token list ${user_q} --output-format json | perl -MJSON::PP -0777 -e 'my \$d=decode_json(<>); for my \$t (@{\$d||[]}) { next unless ref(\$t) eq q{HASH} && defined \$t->{tokenid}; print join(qq{\\t}, \$t->{tokenid}, defined(\$t->{privsep})?\$t->{privsep}:q{}, defined(\$t->{expire})?\$t->{expire}:q{}), qq{\\n}; }'"
        if [[ $RUN_RC -ne 0 ]]; then
            token_failures=$((token_failures+1))
            continue
        fi
        while IFS=$'\t' read -r tokenid privsep expire; do
            [[ -n "$tokenid" ]] || continue
            token_total=$((token_total+1))
            realm="N/A"; [[ "$userid" =~ @([^!]+)$ ]] && realm="${BASH_REMATCH[1]}"
            token_scope="API Token ${userid}!${tokenid}"
            emit_record "$token_scope" "Permissions / API Tokens" "Token / User ID" "$userid" "pveum user token list" "$RUN_TS" "No token secret exported; Evidence=${RUN_EVIDENCE_REL}"
            emit_record "$token_scope" "Permissions / API Tokens" "Token / Token ID" "$tokenid" "pveum user token list" "$RUN_TS" "No token secret exported; Evidence=${RUN_EVIDENCE_REL}"
            emit_record "$token_scope" "Permissions / API Tokens" "Token / Realm" "$realm" "pveum user token list" "$RUN_TS" "Derived from user ID; Evidence=${RUN_EVIDENCE_REL}"
            [[ -n "$privsep" ]] && emit_record "$token_scope" "Permissions / API Tokens" "Token / Privilege Separation" "$privsep" "pveum user token list" "$RUN_TS" "No token secret exported; Evidence=${RUN_EVIDENCE_REL}"
            [[ -n "$expire" ]] && emit_record "$token_scope" "Permissions / API Tokens" "Token / Expire (epoch)" "$expire" "pveum user token list" "$RUN_TS" "No token secret exported; Evidence=${RUN_EVIDENCE_REL}"
        done < "$RUN_STDOUT"
    done < "$USERID_FILE"
    emit_record "$SCOPE" "Permissions / API Tokens" "API Tokens / Total Count" "$token_total" "pveum user token list" "$(date --iso-8601=seconds)" "Metadata only; no secrets"
    if (( token_failures > 0 )); then
        emit_status "$SCOPE" "Permissions / API Tokens" "Token Enumeration" "PARTIAL" "pveum user token list" "$(date --iso-8601=seconds)" "${token_failures} user token-list call(s) unavailable; review Evidence"
    elif (( token_total == 0 )); then
        emit_status "$SCOPE" "Permissions / API Tokens" "Token Inventory" "NO_DATA" "pveum user token list" "$(date --iso-8601=seconds)" "No API tokens returned"
    fi

fi

finish_collector
