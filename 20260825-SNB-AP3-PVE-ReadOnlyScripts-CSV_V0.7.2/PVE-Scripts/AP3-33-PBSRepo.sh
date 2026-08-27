#!/usr/bin/env bash
# AP3 V0.7.2 / PVE - PVE-seitige PBS Storage-/Repository-Konfiguration.
# Secrets/Account-IDs werden nicht exportiert.
set -u
umask 077
SCRIPT_NAME="AP3-33-PBSRepo"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ap3-pve.sh"
source "${SCRIPT_DIR}/../lib/ap3-table.sh"
RUN_ID="${AP3_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"; OUTPUT_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PVE-Out}"; OUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"; OUT_FILE="${OUT_DIR}/${SCRIPT_NAME}_${RUN_ID}.csv"
export AP3_PVE_HOSTS_FILE="${AP3_PVE_HOSTS_FILE:-${SCRIPT_DIR}/pve-hosts.txt}"
PVE_STORAGE_CFG="${AP3_PVE_STORAGE_CFG:-/etc/pve/storage.cfg}"
mkdir -p "$OUT_DIR"
ap3_load_pve_hosts HOSTS "$@"
{
printf '%s\n' "$AP3_DATA_HEADER"
for host in "${HOSTS[@]}"; do
  ts="$(ap3_iso_ts)"; mode="$(ap3_pve_mode "$host")"; suffix="$(ap3_pve_source_suffix "$host")"
  node="$(ap3_pve_capture "$host" "hostname -s 2>/dev/null || hostname" || true)"
  if [[ "$node" == ERROR\(* ]]; then ap3_emit "$host" "Collector/SSH" "PVE access ($mode)" "$node" "hostname ($suffix)" "$ts"; continue; fi
  [[ -n "$node" ]] || node="$host"
  inv_out="$(ap3_pve_capture "$host" "if command -v pvesh >/dev/null 2>&1; then pvesh get /storage; else echo 'NOT_SUPPORTED: pvesh not installed'; fi" || true)"
  inv_records="$(ap3_box_table_records "$inv_out" 2>/dev/null || true)"
  if [[ -n "$inv_records" ]]; then
    while IFS="$AP3_TABLE_SEP" read -r rec storage_id summary; do
      [[ -n "$summary" ]] || continue; [[ -n "$storage_id" ]] || storage_id="record-${rec}"
      ap3_emit "$node / PVE storage $storage_id" "Repository" "PVE storage inventory record" "$summary" "pvesh get /storage ($suffix); Unicode table normalized" "$ts"
    done <<< "$inv_records"
  else
    ap3_emit "$node" "Repository" "PVE storage inventory" "$inv_out" "pvesh get /storage ($suffix)" "$ts"
  fi
  cfg_cmd="$(cat <<REMOTE
awk '
  function mask_user(u, realm, tokenflag, tmp){realm="unknown";tokenflag="no";if(index(u,"@")>0){tmp=u;sub(/^.*@/,"",tmp);sub(/!.*/,"",tmp);realm=tmp}if(index(u,"!")>0)tokenflag="yes";return "realm=" realm "; token-reference=" tokenflag "; account-id=REDACTED"}
  function flush(){if(id!=""){print id"|server|"server;print id"|datastore|"datastore;if(namespace!="")print id"|namespace|"namespace;if(port!="")print id"|port|"port;if(content!="")print id"|content|"content;if(nodes!="")print id"|nodes|"nodes;if(fingerprint!="")print id"|fingerprint|"fingerprint;if(username!="")print id"|username|"mask_user(username);if(disable!="")print id"|disable|"disable;if(encryption!="")print id"|encryption|configured=yes";if(master!="")print id"|master|configured=yes"}id=server=datastore=namespace=port=content=nodes=fingerprint=username=disable=encryption=master=""}
  /^[[:space:]]*pbs:[[:space:]]+/{if(inpbs)flush();id=\$2;inpbs=1;next} inpbs&&/^[^[:space:]]/{flush();inpbs=0} inpbs{key=\$1;\$1="";sub(/^[[:space:]]+/,"",\$0);val=\$0;if(key=="server")server=val;else if(key=="datastore")datastore=val;else if(key=="namespace")namespace=val;else if(key=="port")port=val;else if(key=="content")content=val;else if(key=="nodes")nodes=val;else if(key=="fingerprint")fingerprint=val;else if(key=="username")username=val;else if(key=="disable")disable=val;else if(key=="encryption-key")encryption="present";else if(key=="master-pubkey")master="present"} END{if(inpbs)flush()}
' '$PVE_STORAGE_CFG' 2>/dev/null
REMOTE
)"
  cfg_out="$(ap3_pve_capture "$host" "$cfg_cmd" || true)"
  if [[ "$cfg_out" == ERROR\(* ]]; then ap3_emit "$node" "Repository" "PBS storage configuration" "$cfg_out" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts"; continue; fi
  if [[ -z "$cfg_out" ]]; then ap3_emit "$node" "Repository" "PBS storage configuration" "NOT_CONFIGURED: no PBS storage block found" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts"; continue; fi
  while IFS='|' read -r id key val; do
    [[ -n "$id" ]] || continue; scope="${node} / PVE storage ${id}"
    case "$key" in
      username) ap3_emit "$scope" "Auth" "User/Realm/Token reference" "$val" "$PVE_STORAGE_CFG whitelist; identity redacted ($suffix)" "$ts" ;;
      server) ap3_emit "$scope" "Repository" "PBS server" "$val" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts" ;;
      datastore) ap3_emit "$scope" "Repository" "Datastore" "$val" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts" ;;
      namespace) ap3_emit "$scope" "Repository" "Namespace" "$val" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts" ;;
      port) ap3_emit "$scope" "Connectivity" "PBS port" "$val" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts" ;;
      encryption) ap3_emit "$scope" "Encryption" "Client-side encryption key" "$val" "$PVE_STORAGE_CFG presence only; key not read/exported ($suffix)" "$ts" ;;
      master) ap3_emit "$scope" "Encryption" "Master public key" "$val" "$PVE_STORAGE_CFG presence only; key material not read/exported ($suffix)" "$ts" ;;
      content) ap3_emit "$scope" "Repository" "Content" "$val" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts" ;;
      nodes) ap3_emit "$scope" "Repository" "Nodes restriction" "$val" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts" ;;
      fingerprint) ap3_emit "$scope" "TLS" "Configured fingerprint" "$val" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts" ;;
      disable) ap3_emit "$scope" "Repository" "Disabled" "$val" "$PVE_STORAGE_CFG whitelist ($suffix)" "$ts" ;;
    esac
  done <<< "$cfg_out"
done
} > "$OUT_FILE"
printf '%s\n' "$OUT_FILE"
