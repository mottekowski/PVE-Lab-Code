#!/usr/bin/env bash
# PVE-spezifische Helper fuer AP3 V0.7.2.
# PVE-Collector lokal, weitere PVE-Nodes per SSH. Keine PBS-SSH-Funktion enthalten.
set -u

LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/ap3-csv.sh"

AP3_COLLECTOR_NODE="${AP3_COLLECTOR_NODE:-$(hostname -s 2>/dev/null || hostname)}"
AP3_COLLECTOR_FQDN="${AP3_COLLECTOR_FQDN:-$(hostname -f 2>/dev/null || printf '%s' "$AP3_COLLECTOR_NODE")}"
AP3_SSH_PORT="${AP3_SSH_PORT:-22}"
AP3_SSH_USER="${AP3_SSH_USER:-}"

ap3_read_host_file() {
  local file="$1"
  local -n out_arr="$2"
  out_arr=()
  [[ -r "$file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | xargs)"
    [[ -n "$line" ]] && out_arr+=("$line")
  done < "$file"
}

ap3_is_local_pve() {
  local host="${1%%:*}" short="${1%%.*}"
  [[ "$host" == "$AP3_COLLECTOR_NODE" || "$host" == "$AP3_COLLECTOR_FQDN" || "$short" == "$AP3_COLLECTOR_NODE" ]]
}

ap3_load_pve_hosts() {
  local -n out_arr="$1"
  shift || true
  local -a requested=()
  if (( $# > 0 )); then
    requested=("$@")
  elif [[ -n "${AP3_PVE_HOSTS_FILE:-}" && -r "${AP3_PVE_HOSTS_FILE}" ]]; then
    ap3_read_host_file "${AP3_PVE_HOSTS_FILE}" requested
  fi

  out_arr=("$AP3_COLLECTOR_NODE")
  local h e duplicate
  for h in "${requested[@]}"; do
    [[ -n "$h" ]] || continue
    ap3_is_local_pve "$h" && continue
    duplicate=0
    for e in "${out_arr[@]}"; do
      [[ "$e" == "$h" ]] && { duplicate=1; break; }
    done
    (( duplicate == 0 )) && out_arr+=("$h")
  done
}

ap3_local_capture() {
  local cmd="$1" out rc
  out="$(bash -lc "$cmd" 2>&1)"; rc=$?
  if (( rc == 0 )); then printf '%s' "$out"; else printf 'ERROR(rc=%s): %s' "$rc" "$out"; fi
  return "$rc"
}

ap3_ssh_capture() {
  local host="$1" cmd="$2" target out rc
  if [[ -n "$AP3_SSH_USER" ]]; then target="${AP3_SSH_USER}@${host}"; else target="$host"; fi
  out="$(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes -o LogLevel=ERROR -p "$AP3_SSH_PORT" "$target" "$cmd" 2>&1)"; rc=$?
  if (( rc == 0 )); then printf '%s' "$out"; else printf 'ERROR(rc=%s): %s' "$rc" "$out"; fi
  return "$rc"
}

ap3_pve_capture() {
  local host="$1" cmd="$2"
  if ap3_is_local_pve "$host"; then ap3_local_capture "$cmd"; else ap3_ssh_capture "$host" "$cmd"; fi
}

ap3_pve_mode() { ap3_is_local_pve "$1" && printf 'LOCAL' || printf 'REMOTE'; }
ap3_pve_source_suffix() { ap3_is_local_pve "$1" && printf 'local on collector PVE' || printf 'remote via SSH on PVE'; }
