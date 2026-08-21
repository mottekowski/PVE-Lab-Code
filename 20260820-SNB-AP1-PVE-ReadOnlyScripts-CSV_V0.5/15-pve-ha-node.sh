#!/usr/bin/env bash
# AP1 V0.5 extension - node-local HA watchdog/fencing readiness.
# Read-only only. Never opens /dev/watchdog, never triggers watchdog/fencing, never changes HA state.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "ProxMox_Cluster" "15" "ProxMoxCluster" "PVEHANode"

CATEGORY="HA / Node Watchdog-Fencing"
SCOPE="$HOST_SHORT"
TS="$(date --iso-8601=seconds)"
emit_record "$SCOPE" "$CATEGORY" "Classification" "ARCHITECTURE_CRITICAL / CORE" "AP1 V0.5 scope" "$TS" "Node-local read-only HA baseline"

for unit in pve-ha-lrm pve-ha-crm watchdog-mux; do
    run_capture "systemd-${unit}" "systemctl show ${unit} -p LoadState -p ActiveState -p SubState -p UnitFileState --no-pager" \
      systemctl show "$unit" -p LoadState -p ActiveState -p SubState -p UnitFileState --no-pager
    if [[ $RUN_RC -ne 0 ]]; then
        err="$(head -n 2 "$RUN_STDERR" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
        emit_status "$SCOPE" "$CATEGORY" "Service $unit" "UNAVAILABLE" "systemctl show $unit" "$RUN_TS" "ExitCode=${RUN_RC}; ${err:-service status unavailable}; Evidence=${RUN_EVIDENCE_REL}"
    else
        awk -F= 'NF>=2 {k=$1; sub(/^[^=]*=/,"",$0); print k "\t" $0}' "$RUN_STDOUT" | while IFS=$'\t' read -r key value; do
            emit_record "$SCOPE" "$CATEGORY" "Service $unit / $key" "$value" "systemctl show $unit" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
        done
    fi
done

# Read configured watchdog module only; never access secret/private configuration.
run_capture_shell "watchdog-config" "read WATCHDOG_MODULE from /etc/default/pve-ha-manager" \
  "if [ -r /etc/default/pve-ha-manager ]; then awk -F= '/^[[:space:]]*WATCHDOG_MODULE[[:space:]]*=/{v=\$2; gsub(/^[[:space:]\"]+|[[:space:]\"]+\$/, \"\", v); print v}' /etc/default/pve-ha-manager; fi"
if [[ $RUN_RC -ne 0 ]]; then
    emit_status "$SCOPE" "$CATEGORY" "Watchdog Module" "UNAVAILABLE" "/etc/default/pve-ha-manager" "$RUN_TS" "Unable to read watchdog module setting; Evidence=${RUN_EVIDENCE_REL}"
elif [[ ! -s "$RUN_STDOUT" ]]; then
    emit_record "$SCOPE" "$CATEGORY" "Watchdog / Configured Module" "NOT_EXPLICITLY_CONFIGURED" "/etc/default/pve-ha-manager" "$RUN_TS" "No WATCHDOG_MODULE entry found; no watchdog test performed; Evidence=${RUN_EVIDENCE_REL}"
else
    module="$(head -n1 "$RUN_STDOUT" | tr -d '\r\n')"
    emit_record "$SCOPE" "$CATEGORY" "Watchdog / Configured Module" "$module" "/etc/default/pve-ha-manager" "$RUN_TS" "Read-only; no watchdog test performed; Evidence=${RUN_EVIDENCE_REL}"
fi

# Sysfs-only watchdog inventory. This does not open /dev/watchdog and cannot arm or trigger fencing.
run_capture_shell "watchdog-sysfs" "read /sys/class/watchdog/watchdog*/ identity/state/nowayout/timeout" \
  'found=0; for w in /sys/class/watchdog/watchdog*; do [ -d "$w" ] || continue; found=1; n=$(basename "$w"); printf "%s\tdevice\t%s\n" "$n" "/dev/$n"; for f in identity state nowayout timeout; do if [ -r "$w/$f" ]; then v=$(cat "$w/$f" 2>/dev/null || true); printf "%s\t%s\t%s\n" "$n" "$f" "$v"; fi; done; done; [ "$found" -eq 1 ] || printf "NONE\tstatus\tNO_WATCHDOG_SYSFS_DEVICE\n"'
if [[ $RUN_RC -ne 0 ]]; then
    emit_status "$SCOPE" "$CATEGORY" "Watchdog Device Inventory" "UNAVAILABLE" "/sys/class/watchdog" "$RUN_TS" "Sysfs watchdog inventory failed; Evidence=${RUN_EVIDENCE_REL}"
else
    while IFS=$'\t' read -r dev field value; do
        [[ -n "$dev" ]] || continue
        if [[ "$dev" == "NONE" ]]; then
            emit_status "$SCOPE" "$CATEGORY" "Watchdog Device" "$value" "/sys/class/watchdog" "$RUN_TS" "No device opened; Evidence=${RUN_EVIDENCE_REL}"
        else
            emit_record "$SCOPE" "$CATEGORY" "Watchdog $dev / $field" "$value" "/sys/class/watchdog/$dev/$field" "$RUN_TS" "Sysfs read only; /dev/watchdog never opened; Evidence=${RUN_EVIDENCE_REL}"
        fi
    done < "$RUN_STDOUT"
fi

finish_collector
