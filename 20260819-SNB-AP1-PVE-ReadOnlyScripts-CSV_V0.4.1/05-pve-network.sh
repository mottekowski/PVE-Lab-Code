#!/usr/bin/env bash
# AP1 2.5 - Netzwerk in ProxMox (plattformnah)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "Network_Platform" "05" "NetworkPlatform" "PVENetwork"

run_capture "ip-brief-address" "ip -br a" ip -br a
if run_ready "$HOST_SHORT" "Interfaces" "Interfaces" "ip -br a"; then
    # Only tokens that are actual IPv4/IPv6 CIDR addresses are treated as addresses.
    # This deliberately excludes decorations such as "metric 100" and non-address tokens.
    awk '
      NF>=2 {
        iface=$1; state=$2; addr=""; count=0
        for(i=3;i<=NF;i++) {
          tok=$i
          if (tok ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]+$/ || tok ~ /^[0-9A-Fa-f:]+\/[0-9]+$/) {
            addr=addr (addr?" ":"") tok; count++
          }
        }
        print iface "\tState\t" state
        print iface "\tAddress count\t" count
        print iface "\tAddresses\t" (count?addr:"NONE")
      }
    ' "$RUN_STDOUT" |
    while IFS=$'\t' read -r iface field value; do emit_record "$HOST_SHORT" "Interfaces / $iface" "$field" "$value" "ip -br a" "$RUN_TS" "Read-only; normalized IP/CIDR tokens only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "ip-link-detail" "ip -d link show" ip -d link show
if run_ready "$HOST_SHORT" "Interfaces" "Link Details" "ip -d link show"; then
    awk '
      /^[0-9]+:/ {
        iface=$2; sub(/:$/,"",iface); flags=$3; gsub(/[<>]/,"",flags)
        mtu=""; state=""; master="";
        for(i=4;i<=NF;i++){if($i=="mtu")mtu=$(i+1); if($i=="state")state=$(i+1); if($i=="master")master=$(i+1)}
        print iface "\tFlags\t" flags; if(mtu!="")print iface "\tMTU\t" mtu; if(state!="")print iface "\tState\t" state; if(master!="")print iface "\tMaster\t" master; next
      }
      /^[[:space:]]+link\// {if(iface!=""){print iface "\tLink layer\t" $1; if($2!="")print iface "\tMAC\t" $2}}
      /vlan_filtering/ {for(i=1;i<=NF;i++) if($i=="vlan_filtering") print iface "\tVLAN filtering\t" $(i+1)}
    ' "$RUN_STDOUT" | while IFS=$'\t' read -r iface field value; do emit_record "$HOST_SHORT" "Interfaces / $iface" "$field" "$value" "ip -d link show" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "network-interfaces" "cat /etc/network/interfaces" cat /etc/network/interfaces
if run_ready "$HOST_SHORT" "Bridges/Bonds" "Network Interfaces Config" "cat /etc/network/interfaces"; then
    awk '
      /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
      /^auto[[:space:]]+/ {for(i=2;i<=NF;i++) print $i "\tAuto\tY"; next}
      /^iface[[:space:]]+/ {iface=$2; print iface "\tMethod\t" $3 " " $4; next}
      /^[[:space:]]+/ {line=$0; sub(/^[[:space:]]+/,"",line); split(line,a,/ +/); key=a[1]; v=substr(line,length(key)+2); print iface "\t" key "\t" v}
    ' "$RUN_STDOUT" | while IFS=$'\t' read -r iface field value; do emit_record "$HOST_SHORT" "Bridges/Bonds / $iface" "$field" "$value" "cat /etc/network/interfaces" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

for fam in 4 6; do
    if [[ "$fam" == 4 ]]; then slug="ip-route"; source="ip route"; cmd=(ip route); segment="IPv4 Routing"; else slug="ip6-route"; source="ip -6 route"; cmd=(ip -6 route); segment="IPv6 Routing"; fi
    run_capture "$slug" "$source" "${cmd[@]}"
    if run_ready "$HOST_SHORT" "$segment" "Routes" "$source"; then
        awk 'NF {n++; dest=$1; via=""; dev=""; src=""; metric=""; for(i=2;i<=NF;i++){if($i=="via")via=$(i+1);if($i=="dev")dev=$(i+1);if($i=="src")src=$(i+1);if($i=="metric")metric=$(i+1)} print n "\tDestination\t" dest; if(via!="")print n "\tGateway\t" via; if(dev!="")print n "\tInterface\t" dev; if(src!="")print n "\tSource\t" src; if(metric!="")print n "\tMetric\t" metric}' "$RUN_STDOUT" |
        while IFS=$'\t' read -r n field value; do emit_record "$HOST_SHORT" "$segment" "Route $n / $field" "$value" "$source" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
    fi
done

run_capture "lldp-neighbors" "lldpcli show neighbors" lldpcli show neighbors
if [[ $RUN_RC -ne 0 ]]; then run_ready "$HOST_SHORT" "LLDP" "Neighbors" "lldpcli show neighbors" || true
elif [[ ! -s "$RUN_STDOUT" ]]; then emit_no_data "$HOST_SHORT" "LLDP" "Neighbors" "lldpcli show neighbors" "$RUN_TS" "No LLDP neighbors returned"
else
    emit_kv_colon_file "$HOST_SHORT" "LLDP" "Neighbor" "lldpcli show neighbors" "$RUN_TS" "$RUN_STDOUT" "Read-only"
fi

run_capture "pve-firewall-status" "pve-firewall status" pve-firewall status
if run_ready "$HOST_SHORT" "PVE Firewall" "Status" "pve-firewall status"; then emit_kv_colon_file "$HOST_SHORT" "PVE Firewall" "" "pve-firewall status" "$RUN_TS" "$RUN_STDOUT" "Read-only"; fi

run_capture "iptables-rules" "iptables -S" iptables -S
if run_ready "$HOST_SHORT" "Host Firewall" "iptables" "iptables -S"; then
    awk '/^-P / {print "Policy " $2 "\t" $3} /^-A / {count[$2]++} END{for(c in count) print "Rule count " c "\t" count[c]}' "$RUN_STDOUT" |
    while IFS=$'\t' read -r param value; do emit_record "$HOST_SHORT" "Host Firewall" "$param" "$value" "iptables -S" "$RUN_TS" "Read-only; full rules only in Evidence=${RUN_EVIDENCE_REL}"; done
fi
finish_collector
