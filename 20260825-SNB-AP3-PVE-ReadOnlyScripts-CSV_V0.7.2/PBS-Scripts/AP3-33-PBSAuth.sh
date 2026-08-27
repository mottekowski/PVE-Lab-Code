#!/usr/bin/env bash
# AP3 V0.7.2 / PBS - Auth/Realms/ACL. Identitaeten minimiert; ACLs auf globalen bzw. scoped Datastore-Pfad begrenzt.
set -u
umask 077
SCRIPT_NAME="AP3-33-PBSAuth"; SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; source "${SCRIPT_DIR}/../lib/ap3-pbs.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PBS-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"; AP3_PBS_SCOPE_FILE="${AP3_PBS_SCOPE_FILE:-${SCRIPT_DIR}/Input/AP3_PBS_Scope.csv}"
mkdir -p "$OUT_DIR"; ap3_scope_load "$AP3_PBS_SCOPE_FILE"
{
printf '%s\n' "$AP3_DATA_HEADER"; ts="$(ap3_iso_ts)"; node="$(hostname -s 2>/dev/null || hostname)"
for realmtype in ad ldap openid; do
  raw="$(proxmox-backup-manager "$realmtype" list --output-format json 2>&1)"; rc=$?
  if (( rc != 0 )); then ap3_emit "$node" "Auth" "Realm inventory: $realmtype list" "$(ap3_classify_error "$rc" "$raw")" "local proxmox-backup-manager $realmtype list" "$ts"; continue; fi
  compact="$(printf '%s' "$raw" | tr -d '[:space:]')"
  if [[ -z "$compact" || "$compact" == '[]' ]]; then ap3_emit "$node" "Auth" "Realm inventory: $realmtype list" "NONE_CONFIGURED" "local proxmox-backup-manager $realmtype list" "$ts"; continue; fi
  ap3_emit "$node" "Auth" "Realm inventory: $realmtype list" "CONFIGURED: one or more realms; realm details intentionally not exported on central PBS" "local proxmox-backup-manager $realmtype list --output-format json; presence only" "$ts"
done
users="$(proxmox-backup-manager user list --output-format json 2>/dev/null | grep -o '"userid"' | wc -l || true)"; ap3_emit "$node" "Auth" "Configured user count" "$users" "local proxmox-backup-manager user list (count only; host-wide context)" "$ts"
acl="$(proxmox-backup-manager acl list --output-format text 2>/dev/null | sed -E 's/([[:alnum:]_.-]+)@[[:alnum:]_.-]+(![[:alnum:]_.-]+)?/REDACTED@REALM/g' || true)"
recs="$(ap3_box_table_records "$acl" 2>/dev/null || true)"; emitted=0
if [[ -n "$recs" ]]; then
  while IFS="$AP3_TABLE_SEP" read -r rec first summary; do
    [[ -n "$summary" ]] || continue; keep=0
    case "; $summary; " in *"; path=/; "*|*"; Path=/; "*) keep=1;; esac
    if (( keep == 0 )); then for ds in "${AP3_SCOPE_DATASTORES[@]}"; do [[ "$summary" == *"/datastore/$ds"* ]] && keep=1; done; fi
    if (( keep == 1 )); then ap3_emit "$node" "Permissions" "ACL/Role record $rec" "$summary" "local proxmox-backup-manager acl list; auth IDs redacted; scoped paths only" "$ts"; emitted=1; fi
  done <<< "$recs"
fi
(( emitted == 1 )) || ap3_emit "$node" "Permissions" "ACL/Role summary" "NOT_APPLICABLE: no global or in-scope ACL records exported" "local proxmox-backup-manager acl list; scoped filter" "$ts"
ap3_emit "$node" "Auth" "MFA / Break-Glass process" "NOT_AUTOMATED: organisatorische Validierung erforderlich" "Workshop / PBS GUI" "$ts"
} > "$OUT_FILE"; printf '%s\n' "$OUT_FILE"
