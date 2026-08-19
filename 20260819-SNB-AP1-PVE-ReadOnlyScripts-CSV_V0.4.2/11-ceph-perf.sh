#!/usr/bin/env bash
# AP1 3.5 - Performance-Indikatoren (Read-only)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "Ceph_Cluster" "11" "CephCluster" "CephPerf"
CATEGORY="Performance-Indikatoren"
SCOPE="Ceph-Cluster via ${HOST_SHORT}"

run_capture "osd-perf" "ceph osd perf" ceph osd perf
if run_ready "$SCOPE" "$CATEGORY" "OSD Perf" "ceph osd perf"; then
    awk 'NR>1 && $1~/^[0-9]+$/ {print $1 "\tCommit latency (ms)\t" $2; print $1 "\tApply latency (ms)\t" $3}' "$RUN_STDOUT" | while IFS=$'\t' read -r osd field value; do emit_record "OSD $osd" "$CATEGORY" "$field" "$value" "ceph osd perf" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "ceph-status" "ceph -s" ceph -s
if run_ready "$SCOPE" "$CATEGORY" "Client Latency - Cluster Status" "ceph -s"; then
    health="$(awk '/^[[:space:]]+health:/ {sub(/^.*health:[[:space:]]*/,""); print; exit}' "$RUN_STDOUT")"; [[ -n "$health" ]] && emit_record "$SCOPE" "$CATEGORY" "Client / Health" "$health" "ceph -s" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    io="$(awk 'BEGIN{s=0} /^[[:space:]]{2}io:/ {s=1;next} s && /^[[:space:]]{4}/ {sub(/^[[:space:]]+/,""); print}' "$RUN_STDOUT" | paste -sd ' ' -)"; if [[ -n "$io" ]]; then emit_record "$SCOPE" "$CATEGORY" "Client / IO Summary" "$io" "ceph -s" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; else emit_status "$SCOPE" "$CATEGORY" "Client IO" "NO_DATA" "ceph -s" "$RUN_TS" "No IO section present at collection time; Evidence=${RUN_EVIDENCE_REL}"; fi
fi

run_capture "health-detail" "ceph health detail" ceph health detail
if run_ready "$SCOPE" "$CATEGORY" "Client Latency - Health Detail" "ceph health detail"; then emit_record "$SCOPE" "$CATEGORY" "Client / Health Detail" "$(head -n1 "$RUN_STDOUT")" "ceph health detail" "$RUN_TS" "Read-only; full detail in Evidence=${RUN_EVIDENCE_REL}"; fi

# Capture the complete perf dump for evidence, but normalize only the first 80 raw output lines
# as requested by the AP1 source. V0.3 parses generic scalar counters instead of relying on a
# small fixed counter-name list, which could yield no Data-Capture rows on newer Ceph versions.
run_capture "daemon-perf-dump" "ceph tell osd.* perf dump | head -n 80" ceph tell 'osd.*' perf dump
if run_ready "$SCOPE" "$CATEGORY" "Daemon Perf Sample" "ceph tell osd.* perf dump | head -n 80"; then
    PERF_NORMALIZED="${TMP_ROOT}/daemon-perf-normalized.tsv"
    head -n 80 "$RUN_STDOUT" | awk '
      function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s}
      /^osd\.[0-9]+:/ {
        osd=$1; sub(/:$/, "", osd); section=""; next
      }
      {
        line=$0; sub(/^[[:space:]]+/, "", line)
        if (match(line, /^"[^"]+"[[:space:]]*:[[:space:]]*\{/)) {
          section=line; sub(/^"/, "", section); sub(/"[[:space:]]*:.*/, "", section); next
        }
        if (match(line, /^"[^"]+"[[:space:]]*:[[:space:]]*(-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?|true|false|null)[[:space:]]*,?$/)) {
          key=line; sub(/^"/, "", key); sub(/"[[:space:]]*:.*/, "", key)
          val=line; sub(/^[^:]+:[[:space:]]*/, "", val); sub(/[[:space:]]*,?[[:space:]]*$/, "", val)
          entity=(osd!=""?osd:"OSD sample")
          path=(section!=""?section "/" key:key)
          print entity "\t" path "\t" val
        }
      }
    ' > "$PERF_NORMALIZED"
    if [[ -s "$PERF_NORMALIZED" ]]; then
        while IFS=$'\t' read -r osd path value; do
            emit_record "${SCOPE} / Sample ${osd}" "$CATEGORY" "Daemon Perf Sample / $path" "$value" "ceph tell osd.* perf dump | head -n 80" "$RUN_TS" "SAMPLE_ONLY; cluster-wide Ceph perf sample collected via ${HOST_SHORT}; first 80 raw lines normalized; collector 11 also runs per host for node-local network counters, so this sample can repeat across hosts; full perf dump in Evidence=${RUN_EVIDENCE_REL}"
        done < "$PERF_NORMALIZED"
    else
        emit_status "$SCOPE" "$CATEGORY" "Daemon Perf Sample" "NO_NORMALIZED_COUNTERS" "ceph tell osd.* perf dump | head -n 80" "$RUN_TS" "Command succeeded, but the first 80 raw lines contained no scalar counters matching the generic normalizer; full output retained in Evidence=${RUN_EVIDENCE_REL}"
    fi
fi

run_capture "ip-link-counters" "ip -s link" ip -s link
if run_ready "$HOST_SHORT" "$CATEGORY" "Network (Node) - Link Counter" "ip -s link"; then
    awk '
      /^[0-9]+:/ {iface=$2; sub(/:$/,"",iface); next}
      /^[[:space:]]+RX:/ {getline; print iface "\tRX bytes\t" $1; print iface "\tRX packets\t" $2; print iface "\tRX errors\t" $3; print iface "\tRX dropped\t" $4; next}
      /^[[:space:]]+TX:/ {getline; print iface "\tTX bytes\t" $1; print iface "\tTX packets\t" $2; print iface "\tTX errors\t" $3; print iface "\tTX dropped\t" $4; next}
    ' "$RUN_STDOUT" | while IFS=$'\t' read -r iface field value; do emit_record "$HOST_SHORT / $iface" "$CATEGORY" "Network Counter / $field" "$value" "ip -s link" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

IFACE="${1:-${IFACE:-}}"
if [[ -n "$IFACE" ]]; then
    IFACES=("$IFACE")
else
    # Interface discovery must run on the target node as well. This keeps the
    # coordinator model correct when the collector is invoked through SSH.
    run_capture_shell "interface-discovery" "enumerate physical/bond interfaces via /sys/class/net" 'for p in /sys/class/net/*; do [[ -d "$p" ]] || continue; i="${p##*/}"; [[ "$i" == "lo" ]] && continue; [[ -e "$p/device" || -d "$p/bonding" ]] && printf "%s\n" "$i"; done | sort -u'
    if [[ $RUN_RC -eq 0 ]]; then
        mapfile -t IFACES < "$RUN_STDOUT"
    else
        IFACES=()
        run_ready "$HOST_SHORT" "$CATEGORY" "Network (Node) - Interface Discovery" "enumerate physical/bond interfaces via /sys/class/net" || true
    fi
fi
for iface in "${IFACES[@]}"; do
    run_capture "ethtool-$(printf '%s' "$iface" | tr -c 'A-Za-z0-9._-' '_')" "ethtool -S <IFACE>" ethtool -S "$iface"
    if [[ $RUN_RC -ne 0 ]]; then run_ready "$HOST_SHORT / $iface" "$CATEGORY" "Network (Node) - ethtool" "ethtool -S <IFACE>" || true; continue; fi
    awk -F: 'NF>=2 {k=$1; v=$2; lk=tolower(k); if(lk ~ /(err|drop|crc|disc)/){gsub(/^[ \t]+|[ \t]+$/,"",k);gsub(/^[ \t]+|[ \t]+$/,"",v);if(k!=""&&v!="")print k "\t" v}}' "$RUN_STDOUT" | head -n 50 | while IFS=$'\t' read -r key value; do emit_record "$HOST_SHORT / $iface" "$CATEGORY" "ethtool / $key" "$value" "ethtool -S <IFACE> | head -n 50" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
done
# rados bench ... write --no-cleanup is deliberately excluded because it writes data.
finish_collector
