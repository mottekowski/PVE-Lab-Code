#!/usr/bin/env bash
# AP1 V0.5 additive orchestrator.
# Keeps all V0.4.2 scripts unchanged, runs the existing collector first, then adds V0.5 CORE extensions.

set -u -o pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AP1_TIMEZONE="${AP1_TIMEZONE:-Europe/Berlin}"
RUN_ID="${AP1_RUN_ID:-}"
AP1_SSH_USER="${AP1_SSH_USER:-root}"
CEPH_NODE=""
AUTO_MERGE=1

usage() {
cat <<USAGE
Usage: $0 [options]

Options:
  --run-id YYYYMMDD_HHMM   Fixed run identifier; default current time in AP1 timezone.
  --timezone ZONE          IANA timezone; default Europe/Berlin.
  --ssh-user USER          SSH user for remote PVE nodes; default root.
  --ceph-node NODE         Node for existing cluster-wide Ceph collectors.
  --no-merge               Do not create consolidated CSVs.
  -h, --help               Show help.

V0.5 is additive: existing V0.4.2 scripts are executed unchanged. Afterwards:
  13-pve-permissions.sh  -> cluster-once -> ProxMox_Cluster
  14-pve-ha-core.sh      -> cluster-once -> ProxMox_Cluster
  15-pve-ha-node.sh      -> every ONLINE PVE node -> ProxMox_Cluster
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id) RUN_ID="$2"; shift 2 ;;
        --timezone) AP1_TIMEZONE="$2"; shift 2 ;;
        --ssh-user) AP1_SSH_USER="$2"; shift 2 ;;
        --ceph-node) CEPH_NODE="$2"; shift 2 ;;
        --no-merge) AUTO_MERGE=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

if [[ ! -e "/usr/share/zoneinfo/${AP1_TIMEZONE}" ]]; then
    printf 'Invalid timezone: %s\n' "$AP1_TIMEZONE" >&2; exit 64
fi
export TZ="$AP1_TIMEZONE" AP1_TIMEZONE
[[ -n "$RUN_ID" ]] || RUN_ID="$(date '+%Y%m%d_%H%M')"
if [[ ! "$RUN_ID" =~ ^[0-9]{8}_[0-9]{4}$ ]]; then
    printf 'Invalid run ID: %s (expected YYYYMMDD_HHMM)\n' "$RUN_ID" >&2; exit 64
fi
export AP1_RUN_ID="$RUN_ID" AP1_SSH_USER AP1_TIMEZONE

# Phase 1: unchanged V0.4.2 base collector, suppress merge until V0.5 extensions are complete.
base_args=(--run-id "$RUN_ID" --timezone "$AP1_TIMEZONE" --ssh-user "$AP1_SSH_USER" --no-merge)
[[ -n "$CEPH_NODE" ]] && base_args+=(--ceph-node "$CEPH_NODE")
printf '=== AP1 V0.5 Phase 1/3: unchanged base collection ===\n'
bash "${SCRIPT_DIR}/00-ap1-cluster-collect.sh" "${base_args[@]}"
base_rc=$?

LOCAL_HOST_SHORT="$(hostname -s 2>/dev/null || hostname)"
OUTPUT_ROOT="${SCRIPT_DIR}/outputfiles"
EVIDENCE_ROOT="${SCRIPT_DIR}/evidencefiles"
RUNLOG_DIR="${SCRIPT_DIR}/runlogs/${RUN_ID}"
SUMMARY_FILE="${RUNLOG_DIR}/${RUN_ID}_ExecutionSummary.csv"
mkdir -p "$RUNLOG_DIR" "${OUTPUT_ROOT}/${RUN_ID}" "${EVIDENCE_ROOT}/${RUN_ID}"
if [[ ! -f "$SUMMARY_FILE" ]]; then
    printf 'RunID;Node;Script;Mode;ExitCode;Status;OutputFile;LogFile\n' > "$SUMMARY_FILE"
fi

csv_summary_row() {
    local values=("$@") i v
    for ((i=0; i<${#values[@]}; i++)); do
        v="${values[$i]//\"/\"\"}"
        [[ $i -gt 0 ]] && printf ';' >> "$SUMMARY_FILE"
        printf '"%s"' "$v" >> "$SUMMARY_FILE"
    done
    printf '\n' >> "$SUMMARY_FILE"
}

NODE_JSON="$(mktemp)"; NODE_TSV="$(mktemp)"
trap 'rm -f "$NODE_JSON" "$NODE_TSV"' EXIT
if ! pvesh get /nodes --output-format json > "$NODE_JSON" 2>/dev/null; then
    printf 'ERROR: V0.5 extension node discovery failed.\n' >&2
    exit 2
fi
perl -MJSON::PP -0777 -e 'my $d=decode_json(<>); for my $n (@{$d||[]}) { print join("\t", $n->{node}//"", $n->{status}//""),"\n" if ref($n) eq "HASH" && defined $n->{node}; }' < "$NODE_JSON" > "$NODE_TSV"

is_local_node() { [[ "$1" == "$LOCAL_HOST_SHORT" || "$1" == "$(hostname -f 2>/dev/null || printf '%s' "$LOCAL_HOST_SHORT")" ]]; }
ssh_preflight() {
    local node="$1"; is_local_node "$node" && return 0
    local -a args=(-n -o BatchMode=yes -o "ConnectTimeout=${AP1_SSH_CONNECT_TIMEOUT:-10}" -o LogLevel=ERROR)
    if [[ -n "${AP1_SSH_OPTIONS:-}" ]]; then local -a extra; read -r -a extra <<< "${AP1_SSH_OPTIONS}"; args+=("${extra[@]}"); fi
    ssh "${args[@]}" "${AP1_SSH_USER}@${node}" 'printf AP1_SSH_OK' 2>/dev/null | grep -qx 'AP1_SSH_OK'
}

declare -A NO CAT WHAT
NO[13-pve-permissions.sh]=13; CAT[13-pve-permissions.sh]=ProxMoxCluster; WHAT[13-pve-permissions.sh]=PVEPermissions
NO[14-pve-ha-core.sh]=14;     CAT[14-pve-ha-core.sh]=ProxMoxCluster; WHAT[14-pve-ha-core.sh]=PVEHACore
NO[15-pve-ha-node.sh]=15;     CAT[15-pve-ha-node.sh]=ProxMoxCluster; WHAT[15-pve-ha-node.sh]=PVEHANode

run_ext() {
    local node="$1" script="$2" mode="$3" safe out log rc status errors
    safe="$(printf '%s' "$node" | tr -c 'A-Za-z0-9._-' '_')"
    out="${OUTPUT_ROOT}/${RUN_ID}/${RUN_ID}_${NO[$script]}_${safe}_${CAT[$script]}_${WHAT[$script]}.csv"
    log="${RUNLOG_DIR}/${RUN_ID}_${NO[$script]}_${safe}_${script%.sh}.log"
    printf '[%s] %s -> %s (%s)\n' "$(date '+%H:%M:%S')" "$script" "$node" "$mode"
    AP1_TARGET_HOST="$node" AP1_RUN_ID="$RUN_ID" AP1_SSH_USER="$AP1_SSH_USER" \
      AP1_OUTPUT_ROOT="$OUTPUT_ROOT" AP1_EVIDENCE_ROOT="$EVIDENCE_ROOT" AP1_TIMEZONE="$AP1_TIMEZONE" \
      AP1_SSH_CONNECT_TIMEOUT="${AP1_SSH_CONNECT_TIMEOUT:-10}" AP1_SSH_OPTIONS="${AP1_SSH_OPTIONS:-}" \
      bash "${SCRIPT_DIR}/${script}" </dev/null > "$log" 2>&1
    rc=$?
    if [[ $rc -ne 0 ]]; then status=SCRIPT_FAILED
    elif [[ ! -f "$out" ]]; then status=OUTPUT_MISSING; rc=3
    else
        errors="$(grep -c ';"ERROR";' "$out" 2>/dev/null || true)"
        if [[ "$errors" -gt 0 ]]; then status=COMPLETED_WITH_COLLECTOR_ERRORS; else status=OK; fi
    fi
    csv_summary_row "$RUN_ID" "$node" "$script" "$mode" "$rc" "$status" "$out" "$log"
    [[ $rc -eq 0 ]]
}

printf '\n=== AP1 V0.5 Phase 2/3: additive CORE extensions ===\n'
failures=0
[[ $base_rc -eq 0 ]] || failures=$((failures+1))

# Cluster-wide permissions and HA core once on coordinator.
for script in 13-pve-permissions.sh 14-pve-ha-core.sh; do
    run_ext "$LOCAL_HOST_SHORT" "$script" "cluster-once-v05" || failures=$((failures+1))
done

# Node-local HA watchdog/fencing baseline on every ONLINE node.
while IFS=$'\t' read -r node status; do
    [[ -n "$node" ]] || continue
    if [[ "$status" != "online" ]]; then
        csv_summary_row "$RUN_ID" "$node" "15-pve-ha-node.sh" "all-host-v05" "4" "SKIPPED_NODE_NOT_ONLINE" "" ""
        failures=$((failures+1)); continue
    fi
    if ! ssh_preflight "$node"; then
        csv_summary_row "$RUN_ID" "$node" "15-pve-ha-node.sh" "all-host-v05" "5" "SKIPPED_SSH_UNAVAILABLE" "" ""
        failures=$((failures+1)); continue
    fi
    run_ext "$node" "15-pve-ha-node.sh" "all-host-v05" || failures=$((failures+1))
done < "$NODE_TSV"

# V0.5 coverage gate.
for script in 13-pve-permissions.sh 14-pve-ha-core.sh; do
    out="${OUTPUT_ROOT}/${RUN_ID}/${RUN_ID}_${NO[$script]}_${LOCAL_HOST_SHORT}_${CAT[$script]}_${WHAT[$script]}.csv"
    if [[ ! -f "$out" ]]; then csv_summary_row "$RUN_ID" "$LOCAL_HOST_SHORT" "$script" "coverage-v05" "7" "COVERAGE_MISSING" "$out" ""; failures=$((failures+1)); fi
done
while IFS=$'\t' read -r node status; do
    [[ "$status" == "online" ]] || continue
    safe="$(printf '%s' "$node" | tr -c 'A-Za-z0-9._-' '_')"
    out="${OUTPUT_ROOT}/${RUN_ID}/${RUN_ID}_15_${safe}_ProxMoxCluster_PVEHANode.csv"
    if [[ ! -f "$out" ]]; then csv_summary_row "$RUN_ID" "$node" "15-pve-ha-node.sh" "coverage-v05" "7" "COVERAGE_MISSING" "$out" ""; failures=$((failures+1)); fi
done < "$NODE_TSV"

printf '\n=== AP1 V0.5 Phase 3/3: existing merge ===\n'
if [[ $AUTO_MERGE -eq 1 ]]; then
    bash "${SCRIPT_DIR}/90-ap1-merge.sh" "$RUN_ID" || failures=$((failures+1))
fi

printf '\nAP1 V0.5 Run ID: %s\n' "$RUN_ID"
printf 'Timezone: %s (%s, %s)\n' "$AP1_TIMEZONE" "$(date '+%Z')" "$(date '+%:z')"
printf 'Output directory: %s\n' "${OUTPUT_ROOT}/${RUN_ID}"
printf 'Execution summary: %s\n' "$SUMMARY_FILE"
[[ $AUTO_MERGE -eq 1 ]] && printf 'Merged directory: %s\n' "${SCRIPT_DIR}/mergedfiles/${RUN_ID}"
if [[ $failures -gt 0 ]]; then
    printf 'AP1 V0.5 completed with %d issue(s). Review ExecutionSummary and Collector Status rows.\n' "$failures" >&2
    exit 2
fi
printf 'AP1 V0.5 completed without orchestration errors.\n'
