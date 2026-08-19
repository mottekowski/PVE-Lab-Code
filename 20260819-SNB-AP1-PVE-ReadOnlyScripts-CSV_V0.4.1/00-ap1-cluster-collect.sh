#!/usr/bin/env bash
# AP1 V0.4.1 central cluster collector.
# Discovers PVE cluster nodes, executes the defined read-only collectors locally/through SSH,
# and keeps all CSV/evidence files on the coordinator host.

set -u -o pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUN_ID="${AP1_RUN_ID:-$(date '+%Y%m%d_%H%M')}"
AP1_SSH_USER="${AP1_SSH_USER:-root}"
CEPH_NODE=""
AUTO_MERGE=1

usage() {
    cat <<USAGE
Usage: $0 [options]

Options:
  --run-id YYYYMMDD_HHMM   Fixed run identifier. Default: current local date/time.
  --ssh-user USER          SSH user for remote PVE nodes. Default: root.
  --ceph-node NODE         Node used for cluster-wide Ceph collectors 07-10 and 12.
                           Default: coordinator host.
  --no-merge               Do not create consolidated CSV files after collection.
  -h, --help               Show this help.

Environment:
  AP1_SSH_OPTIONS          Additional whitespace-separated OpenSSH options.
  AP1_SSH_CONNECT_TIMEOUT SSH connect timeout in seconds (default 10).

The coordinator requires passwordless/non-interactive SSH to the remote PVE nodes.
No script package or OUTPUT file is copied to remote nodes. Only read-only commands are
executed through SSH; stdout/stderr are captured on the coordinator.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id) AP1_RUN_ID="$2"; RUN_ID="$2"; shift 2 ;;
        --ssh-user) AP1_SSH_USER="$2"; shift 2 ;;
        --ceph-node) CEPH_NODE="$2"; shift 2 ;;
        --no-merge) AUTO_MERGE=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

if [[ ! "$RUN_ID" =~ ^[0-9]{8}_[0-9]{4}$ ]]; then
    printf 'Invalid --run-id: %s (expected YYYYMMDD_HHMM)\n' "$RUN_ID" >&2
    exit 64
fi

export AP1_RUN_ID="$RUN_ID" AP1_SSH_USER
export AP1_OUTPUT_ROOT="${SCRIPT_DIR}/outputfiles"
export AP1_EVIDENCE_ROOT="${SCRIPT_DIR}/evidencefiles"
export AP1_TARGET_HOST="$(hostname -s 2>/dev/null || hostname)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "ProxMox_Cluster" "00" "ProxMoxCluster" "ClusterNodes"

RUNLOG_DIR="${SCRIPT_DIR}/runlogs/${RUN_ID}"
mkdir -p "$RUNLOG_DIR"
SUMMARY_FILE="${RUNLOG_DIR}/${RUN_ID}_ExecutionSummary.csv"
printf 'RunID;Node;Script;Mode;ExitCode;Status;OutputFile;LogFile\n' > "$SUMMARY_FILE"

csv_summary_row() {
    local values=("$@") i v
    for ((i=0; i<${#values[@]}; i++)); do
        v="${values[$i]//\"/\"\"}"
        [[ $i -gt 0 ]] && printf ';' >> "$SUMMARY_FILE"
        printf '"%s"' "$v" >> "$SUMMARY_FILE"
    done
    printf '\n' >> "$SUMMARY_FILE"
}

# 1) Discover all configured cluster nodes from the coordinator.
run_capture "cluster-nodes" "pvesh get /nodes --output-format json" pvesh get /nodes --output-format json
if ! run_ready "PVE-Cluster via ${LOCAL_HOST_SHORT}" "Cluster Node Discovery" "Cluster Nodes" "pvesh get /nodes --output-format json"; then
    printf 'ERROR: Cluster node discovery failed. See %s\n' "$RUN_EVIDENCE" >&2
    exit 2
fi

NODE_TSV="${TMP_ROOT}/nodes.tsv"
perl -MJSON::PP -0777 -e '
    my $d=decode_json(<>);
    die "Expected JSON array\n" unless ref($d) eq "ARRAY";
    for my $n (@$d) {
        next unless ref($n) eq "HASH" && defined $n->{node};
        print join("\t", map { defined($_) ? $_ : "" } ($n->{node}, $n->{status}, $n->{maxcpu}, $n->{maxmem}, $n->{mem}, $n->{uptime})), "\n";
    }
' < "$RUN_STDOUT" > "$NODE_TSV"

if [[ ! -s "$NODE_TSV" ]]; then
    emit_status "PVE-Cluster via ${LOCAL_HOST_SHORT}" "Cluster Node Discovery" "Nodes" "NO_DATA" "pvesh get /nodes --output-format json" "$RUN_TS" "No cluster nodes returned; Evidence=${RUN_EVIDENCE_REL}"
    printf 'ERROR: no cluster nodes discovered.\n' >&2
    exit 2
fi

mapfile -t ALL_NODES < <(cut -f1 "$NODE_TSV")
while IFS=$'\t' read -r node status maxcpu maxmem mem uptime; do
    emit_record "$node" "Cluster Node Discovery" "Node / Status" "${status:-unknown}" "pvesh get /nodes" "$RUN_TS" "Coordinator=${LOCAL_HOST_SHORT}; Evidence=${RUN_EVIDENCE_REL}"
    [[ -n "$maxcpu" ]] && emit_record "$node" "Cluster Node Discovery" "Node / maxcpu" "$maxcpu" "pvesh get /nodes" "$RUN_TS" "Coordinator=${LOCAL_HOST_SHORT}; Evidence=${RUN_EVIDENCE_REL}"
    [[ -n "$maxmem" ]] && emit_record "$node" "Cluster Node Discovery" "Node / maxmem (bytes)" "$maxmem" "pvesh get /nodes" "$RUN_TS" "Coordinator=${LOCAL_HOST_SHORT}; Evidence=${RUN_EVIDENCE_REL}"
    [[ -n "$mem" ]] && emit_record "$node" "Cluster Node Discovery" "Node / mem (bytes)" "$mem" "pvesh get /nodes" "$RUN_TS" "Coordinator=${LOCAL_HOST_SHORT}; Evidence=${RUN_EVIDENCE_REL}"
    [[ -n "$uptime" ]] && emit_record "$node" "Cluster Node Discovery" "Node / uptime (s)" "$uptime" "pvesh get /nodes" "$RUN_TS" "Coordinator=${LOCAL_HOST_SHORT}; Evidence=${RUN_EVIDENCE_REL}"
done < "$NODE_TSV"

# Maps are also used to locate the generated file for run status checks.
declare -A COLLECTOR_NO FILE_CATEGORY FILE_WHAT
COLLECTOR_NO[01-pve-info.sh]=01;       FILE_CATEGORY[01-pve-info.sh]=ProxMoxCluster; FILE_WHAT[01-pve-info.sh]=PVEInfo
COLLECTOR_NO[02-pve-cluster.sh]=02;    FILE_CATEGORY[02-pve-cluster.sh]=ProxMoxCluster; FILE_WHAT[02-pve-cluster.sh]=PVECluster
COLLECTOR_NO[03-pve-ha.sh]=03;         FILE_CATEGORY[03-pve-ha.sh]=ProxMoxCluster; FILE_WHAT[03-pve-ha.sh]=PVEHA
COLLECTOR_NO[04-pve-storage.sh]=04;    FILE_CATEGORY[04-pve-storage.sh]=ProxMoxCluster; FILE_WHAT[04-pve-storage.sh]=PVEStorage
COLLECTOR_NO[05-pve-network.sh]=05;    FILE_CATEGORY[05-pve-network.sh]=NetworkPlatform; FILE_WHAT[05-pve-network.sh]=PVENetwork
COLLECTOR_NO[06-pve-ops.sh]=06;        FILE_CATEGORY[06-pve-ops.sh]=ProxMoxCluster; FILE_WHAT[06-pve-ops.sh]=PVEOps
COLLECTOR_NO[07-ceph-status.sh]=07;     FILE_CATEGORY[07-ceph-status.sh]=CephCluster; FILE_WHAT[07-ceph-status.sh]=CephStatus
COLLECTOR_NO[08-ceph-topology.sh]=08;  FILE_CATEGORY[08-ceph-topology.sh]=CephCluster; FILE_WHAT[08-ceph-topology.sh]=CephTopology
COLLECTOR_NO[09-ceph-pools.sh]=09;     FILE_CATEGORY[09-ceph-pools.sh]=CephCluster; FILE_WHAT[09-ceph-pools.sh]=CephPools
COLLECTOR_NO[10-ceph-capacity.sh]=10;  FILE_CATEGORY[10-ceph-capacity.sh]=CephCluster; FILE_WHAT[10-ceph-capacity.sh]=CephCapacity
COLLECTOR_NO[11-ceph-perf.sh]=11;      FILE_CATEGORY[11-ceph-perf.sh]=CephCluster; FILE_WHAT[11-ceph-perf.sh]=CephPerf
COLLECTOR_NO[12-ceph-recovery.sh]=12;  FILE_CATEGORY[12-ceph-recovery.sh]=CephCluster; FILE_WHAT[12-ceph-recovery.sh]=CephRecovery

ALL_HOST_SCRIPTS=(01-pve-info.sh 02-pve-cluster.sh 03-pve-ha.sh 04-pve-storage.sh 05-pve-network.sh 06-pve-ops.sh 11-ceph-perf.sh)
CLUSTER_ONCE_SCRIPTS=(07-ceph-status.sh 08-ceph-topology.sh 09-ceph-pools.sh 10-ceph-capacity.sh 12-ceph-recovery.sh)

is_local_node() {
    local n="$1"
    [[ "$n" == "$LOCAL_HOST_SHORT" || "$n" == "$LOCAL_HOST_FQDN" ]]
}

ssh_preflight() {
    local node="$1"
    is_local_node "$node" && return 0
    local -a args
    args=(-n -o BatchMode=yes -o "ConnectTimeout=${AP1_SSH_CONNECT_TIMEOUT:-10}" -o LogLevel=ERROR)
    if [[ -n "${AP1_SSH_OPTIONS:-}" ]]; then
        local -a extra
        read -r -a extra <<< "${AP1_SSH_OPTIONS}"
        args+=("${extra[@]}")
    fi
    ssh "${args[@]}" "${AP1_SSH_USER}@${node}" 'printf AP1_SSH_OK' 2>/dev/null | grep -qx 'AP1_SSH_OK'
}

run_collector() {
    local node="$1" script="$2" mode="$3"
    local safe_node out log rc status errors
    safe_node="$(printf '%s' "$node" | tr -c 'A-Za-z0-9._-' '_')"
    out="${AP1_OUTPUT_ROOT}/${RUN_ID}/${RUN_ID}_${COLLECTOR_NO[$script]}_${safe_node}_${FILE_CATEGORY[$script]}_${FILE_WHAT[$script]}.csv"
    log="${RUNLOG_DIR}/${RUN_ID}_${COLLECTOR_NO[$script]}_${safe_node}_${script%.sh}.log"
    printf '[%s] %s -> %s (%s)\n' "$(date '+%H:%M:%S')" "$script" "$node" "$mode"
    AP1_TARGET_HOST="$node" AP1_RUN_ID="$RUN_ID" AP1_SSH_USER="$AP1_SSH_USER" \
      AP1_OUTPUT_ROOT="$AP1_OUTPUT_ROOT" AP1_EVIDENCE_ROOT="$AP1_EVIDENCE_ROOT" \
      AP1_SSH_CONNECT_TIMEOUT="${AP1_SSH_CONNECT_TIMEOUT:-10}" AP1_SSH_OPTIONS="${AP1_SSH_OPTIONS:-}" \
      bash "${SCRIPT_DIR}/${script}" </dev/null >"$log" 2>&1
    rc=$?
    if [[ $rc -ne 0 ]]; then
        status="SCRIPT_FAILED"
    elif [[ ! -f "$out" ]]; then
        status="OUTPUT_MISSING"
        rc=3
    else
        errors="$(grep -c ';"ERROR";' "$out" 2>/dev/null || true)"
        if [[ "$errors" -gt 0 ]]; then status="COMPLETED_WITH_COLLECTOR_ERRORS"; else status="OK"; fi
    fi
    csv_summary_row "$RUN_ID" "$node" "$script" "$mode" "$rc" "$status" "$out" "$log"
    [[ $rc -eq 0 ]]
}

failures=0

# 2) Execute host-relevant collectors on every ONLINE cluster node.
while IFS=$'\t' read -r node status _; do
    if [[ "$status" != "online" ]]; then
        csv_summary_row "$RUN_ID" "$node" "ALL_HOST_SCRIPTS" "all-host" "4" "SKIPPED_NODE_NOT_ONLINE" "" ""
        failures=$((failures+1))
        continue
    fi
    if ! ssh_preflight "$node"; then
        csv_summary_row "$RUN_ID" "$node" "ALL_HOST_SCRIPTS" "all-host" "5" "SKIPPED_SSH_UNAVAILABLE" "" ""
        printf 'WARNING: SSH preflight failed for %s.\n' "$node" >&2
        failures=$((failures+1))
        continue
    fi
    for script in "${ALL_HOST_SCRIPTS[@]}"; do
        run_collector "$node" "$script" "all-host" || failures=$((failures+1))
    done
done < "$NODE_TSV"

# 2b) Coverage gate: every ONLINE node must have one output file for every all-host collector.
# This catches orchestration gaps even if a loop or child process terminates unexpectedly.
while IFS=$'\t' read -r node status _; do
    [[ "$status" == "online" ]] || continue
    safe_node="$(printf '%s' "$node" | tr -c 'A-Za-z0-9._-' '_')"
    for script in "${ALL_HOST_SCRIPTS[@]}"; do
        out="${AP1_OUTPUT_ROOT}/${RUN_ID}/${RUN_ID}_${COLLECTOR_NO[$script]}_${safe_node}_${FILE_CATEGORY[$script]}_${FILE_WHAT[$script]}.csv"
        if [[ ! -f "$out" ]]; then
            printf 'ERROR: coverage check: expected output missing for %s / %s.\n' "$node" "$script" >&2
            csv_summary_row "$RUN_ID" "$node" "$script" "coverage-check" "7" "COVERAGE_MISSING" "$out" ""
            failures=$((failures+1))
        fi
    done
done < "$NODE_TSV"

# 3) Execute cluster-wide Ceph collectors once. Default target is the coordinator.
if [[ -z "$CEPH_NODE" ]]; then CEPH_NODE="$LOCAL_HOST_SHORT"; fi
if ! grep -q "^${CEPH_NODE}"$'\t' "$NODE_TSV"; then
    printf 'ERROR: Ceph collection node %s is not in the discovered PVE node list.\n' "$CEPH_NODE" >&2
    csv_summary_row "$RUN_ID" "$CEPH_NODE" "CLUSTER_ONCE_SCRIPTS" "cluster-once" "6" "INVALID_CEPH_NODE" "" ""
    failures=$((failures+1))
elif ! ssh_preflight "$CEPH_NODE"; then
    printf 'ERROR: SSH/preflight failed for Ceph collection node %s.\n' "$CEPH_NODE" >&2
    csv_summary_row "$RUN_ID" "$CEPH_NODE" "CLUSTER_ONCE_SCRIPTS" "cluster-once" "5" "SSH_UNAVAILABLE" "" ""
    failures=$((failures+1))
else
    for script in "${CLUSTER_ONCE_SCRIPTS[@]}"; do
        run_collector "$CEPH_NODE" "$script" "cluster-once" || failures=$((failures+1))
    done
fi

finish_collector

# 4) Build import/review CSVs with one header and all host rows.
if [[ $AUTO_MERGE -eq 1 ]]; then
    if ! bash "${SCRIPT_DIR}/90-ap1-merge.sh" "$RUN_ID"; then
        failures=$((failures+1))
    fi
fi

printf '\nRun ID: %s\n' "$RUN_ID"
printf 'Discovered nodes: %s\n' "${ALL_NODES[*]}"
printf 'Output directory: %s\n' "${AP1_OUTPUT_ROOT}/${RUN_ID}"
printf 'Evidence directory: %s\n' "${AP1_EVIDENCE_ROOT}/${RUN_ID}"
printf 'Execution summary: %s\n' "$SUMMARY_FILE"
[[ $AUTO_MERGE -eq 1 ]] && printf 'Merged directory: %s\n' "${SCRIPT_DIR}/mergedfiles/${RUN_ID}"

if [[ $failures -gt 0 ]]; then
    printf 'Collection completed with %d execution/preflight issue(s). Review the summary and Collector Status rows.\n' "$failures" >&2
    exit 2
fi
printf 'Collection completed without orchestration errors.\n'
