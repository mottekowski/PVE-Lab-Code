#!/usr/bin/env bash
# AP3 V0.7.2 / PVE - Netzwerkpfad und Namensaufloesung PVE -> PBS.
# Keine SSH-Verbindung zum PBS; nur PVE-seitige Read-only-Abfragen und passive/geringe Netzwerkproben.
set -u
umask 077
SCRIPT_NAME="AP3-31-PBSNet"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ap3-pve.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"
OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PVE-Out}"
OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"
OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"
export AP3_PVE_HOSTS_FILE="${AP3_PVE_HOSTS_FILE:-${SCRIPT_DIR}/pve-hosts.txt}"
PVE_STORAGE_CFG="${AP3_PVE_STORAGE_CFG:-/etc/pve/storage.cfg}"
mkdir -p "$OUT_DIR"
safe_endpoint(){ [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]; }
ap3_load_pve_hosts HOSTS "$@"
{
printf '%s\n' "$AP3_DATA_HEADER"
for host in "${HOSTS[@]}"; do
  ts="$(ap3_iso_ts)"; mode="$(ap3_pve_mode "$host")"; suffix="$(ap3_pve_source_suffix "$host")"
  node="$(ap3_pve_capture "$host" "hostname -s 2>/dev/null || hostname" || true)"
  if [[ "$node" == ERROR\(* ]]; then ap3_emit "$host" "Collector/SSH" "PVE access ($mode)" "$node" "hostname ($suffix)" "$ts"; continue; fi
  [[ -n "$node" ]] || node="$host"
  ap3_emit "$node" "Collector" "Execution mode" "$mode; collector=${AP3_COLLECTOR_NODE}; environment=PVE" "collector runtime" "$ts"
  discover_cmd="awk '/^[[:space:]]*pbs:[[:space:]]+/{id=\$2;inpbs=1;next} inpbs&&/^[^[:space:]]/{inpbs=0} inpbs&&\$1==\"server\"{print id\"|\"\$2}' '$PVE_STORAGE_CFG' 2>/dev/null | awk -F'|' 'NF==2&&\$2!=\"\"&&!seen[\$1 FS \$2]++'"
  targets="$(ap3_pve_capture "$host" "$discover_cmd" || true)"
  if [[ "$targets" == ERROR\(* ]]; then ap3_emit "$node" "Connectivity" "PBS target discovery" "$targets" "$PVE_STORAGE_CFG ($suffix)" "$ts"; continue; fi
  if [[ -z "$targets" ]]; then ap3_emit "$node" "Connectivity" "PBS target discovery" "NOT_CONFIGURED: no PBS storage server entry found" "$PVE_STORAGE_CFG ($suffix)" "$ts"; continue; fi
  while IFS='|' read -r storage_id server; do
    [[ -n "$server" ]] || continue
    if ! safe_endpoint "$server"; then ap3_emit "$node -> $storage_id" "Connectivity" "PBS endpoint validation" "COLLECTION_FAILED(rc=64): unsupported endpoint characters" "$PVE_STORAGE_CFG ($suffix)" "$ts"; continue; fi
    scope="${node} -> ${storage_id} (${server})"
    dns_out="$(ap3_pve_capture "$host" "getent hosts -- '$server'" || true)"; ap3_emit "$scope" "Connectivity" "DNS/Hosts resolution" "$dns_out" "getent hosts <pbs-fqdn> ($suffix)" "$ts"
    ping_out="$(ap3_pve_capture "$host" "ping -c 5 -- '$server'" || true)"; ap3_emit "$scope" "Connectivity" "Reachability / RTT" "$ping_out" "ping -c 5 <pbs-fqdn> ($suffix)" "$ts"
    ip="$(ap3_pve_capture "$host" "getent ahostsv4 '$server' 2>/dev/null | awk 'NR==1{print \$1}'" || true)"
    if [[ "$ip" == ERROR\(* ]] || [[ -z "$ip" ]] || ! safe_endpoint "$ip"; then
      ap3_emit "$scope" "Connectivity" "Network path" "NOT_EXECUTED: no valid IPv4 address resolved" "traceroute -n <pbs-ip> ($suffix)" "$ts"
    else
      route_out="$(ap3_pve_capture "$host" "ip route get '$ip'" || true)"; ap3_emit "$scope" "Connectivity" "Local route to PBS" "$route_out" "ip route get <pbs-ip> ($suffix)" "$ts"
      trace_out="$(ap3_pve_capture "$host" "if command -v traceroute >/dev/null 2>&1; then traceroute -n '$ip'; else echo 'NOT_SUPPORTED: traceroute not installed'; fi" || true)"; ap3_emit "$scope" "Connectivity" "Network path" "$trace_out" "traceroute -n <pbs-ip> ($suffix)" "$ts"
    fi
    ap3_emit "$scope" "Connectivity" "SSH dependency" "NOT_APPLICABLE: PVE->PBS SSH/TCP22 is not used by AP3 V0.7.2" "collector architecture" "$ts"
  done <<< "$targets"
done
} > "$OUT_FILE"
printf '%s\n' "$OUT_FILE"
