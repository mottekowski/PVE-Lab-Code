#!/usr/bin/env bash
# AP3 V0.7.2 / PVE - TLS-Zertifikatspruefung PVE -> PBS ueber TCP/8007.
set -u
umask 077
SCRIPT_NAME="AP3-32-PBSTLS"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ap3-pve.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PVE-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"
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
  discover_cmd="awk '/^[[:space:]]*pbs:[[:space:]]+/{id=\$2;inpbs=1;next} inpbs&&/^[^[:space:]]/{inpbs=0} inpbs&&\$1==\"server\"{print id\"|\"\$2}' '$PVE_STORAGE_CFG' 2>/dev/null | awk -F'|' 'NF==2&&\$2!=\"\"&&!seen[\$1 FS \$2]++'"
  targets="$(ap3_pve_capture "$host" "$discover_cmd" || true)"
  if [[ "$targets" == ERROR\(* ]] || [[ -z "$targets" ]]; then ap3_emit "$node" "TLS" "PBS target discovery" "${targets:-NOT_CONFIGURED: no PBS target}" "$PVE_STORAGE_CFG ($suffix)" "$ts"; continue; fi
  while IFS='|' read -r storage_id server; do
    [[ -n "$server" ]] || continue
    if ! safe_endpoint "$server"; then ap3_emit "$node -> $storage_id" "TLS" "PBS endpoint validation" "COLLECTION_FAILED(rc=64): unsupported endpoint characters" "$PVE_STORAGE_CFG ($suffix)" "$ts"; continue; fi
    scope="${node} -> ${storage_id} (${server})"
    cert_out="$(ap3_pve_capture "$host" "if ! command -v openssl >/dev/null 2>&1; then echo 'NOT_SUPPORTED: openssl not installed'; exit 0; fi; timeout 15 openssl s_client -connect '${server}:8007' -servername '$server' -showcerts </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 -subject -issuer -dates" || true)"
    ap3_emit "$scope" "TLS" "Certificate fingerprint / identity / validity" "$cert_out" "openssl s_client :8007 | openssl x509 ($suffix)" "$ts"
  done <<< "$targets"
done
} > "$OUT_FILE"
printf '%s\n' "$OUT_FILE"
