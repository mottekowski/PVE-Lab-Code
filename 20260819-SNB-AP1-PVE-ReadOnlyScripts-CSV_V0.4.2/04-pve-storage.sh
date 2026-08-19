#!/usr/bin/env bash
# AP1 2.4 - Storage in ProxMox
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ap1-csv-common.sh"
collector_init "ProxMox_Cluster" "04" "ProxMoxCluster" "PVEStorage"
CATEGORY="Storage in ProxMox"
SCOPE="PVE-Cluster via ${HOST_SHORT}"
NODE="${NODE:-$HOST_SHORT}"

run_capture "pvesm-status" "pvesm status" pvesm status
if run_ready "$SCOPE" "$CATEGORY" "Storage Definitionen" "pvesm status"; then
    awk 'NR>1 && NF>=7 {name=$1; print name "\tType\t" $2; print name "\tStatus\t" $3; print name "\tTotal KiB\t" $4; print name "\tUsed KiB\t" $5; print name "\tAvailable KiB\t" $6; print name "\tUsed Percent\t" $7}' "$RUN_STDOUT" |
    while IFS=$'\t' read -r storage field value; do emit_record "Storage $storage" "$CATEGORY" "Storage / $field" "$value" "pvesm status" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi
# pvesm status --verbose is deliberately excluded because it is red-marked in the source document.

run_capture "storage-cfg" "cat /etc/pve/storage.cfg" cat /etc/pve/storage.cfg
if run_ready "$SCOPE" "$CATEGORY" "Storage Konfig" "cat /etc/pve/storage.cfg"; then
    awk '
      /^[[:space:]]*$/ || /^[[:space:]]*#/ {next}
      /^[^[:space:]][^:]*:[[:space:]]*/ {line=$0; pos=index(line,":"); type=substr(line,1,pos-1); id=substr(line,pos+1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",type);gsub(/^[[:space:]]+|[[:space:]]+$/,"",id); print id "\tType\t" type; next}
      /^[[:space:]]+/ {line=$0; sub(/^[[:space:]]+/,"",line); split(line,a,/ +/); key=a[1]; v=substr(line,length(key)+2); print id "\t" key "\t" v}
    ' "$RUN_STDOUT" | while IFS=$'\t' read -r storage field value; do emit_record "Storage $storage" "$CATEGORY" "Definition / $field" "$value" "cat /etc/pve/storage.cfg" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"; done
fi

run_capture "pve-ceph-status-json" "pvesh get /cluster/ceph/status --output-format json" pvesh get /cluster/ceph/status --output-format json
if run_ready "$SCOPE" "$CATEGORY" "Ceph in PVE" "pvesh get /cluster/ceph/status --output-format json"; then
    json_object_fields "$RUN_STDOUT" fsid election_epoch health.status quorum_names monmap.num_mons osdmap.osdmap.num_osds osdmap.osdmap.num_up_osds osdmap.osdmap.num_in_osds pgmap.num_pgs pgmap.bytes_used pgmap.bytes_avail pgmap.bytes_total | while IFS=$'\t' read -r field value; do
        emit_record "$SCOPE" "$CATEGORY" "Ceph Status / $field" "$value" "pvesh get /cluster/ceph/status" "$RUN_TS" "Selected scalar only; full JSON in Evidence=${RUN_EVIDENCE_REL}"
    done
fi

run_capture "qm-list" "qm list" qm list
if run_ready "$SCOPE" "$CATEGORY" "VM Disks" "qm list"; then
    mapfile -t VMIDS < <(awk 'NR>1 && $1~/^[0-9]+$/ {print $1}' "$RUN_STDOUT")
    if [[ ${#VMIDS[@]} -eq 0 ]]; then emit_no_data "$SCOPE" "$CATEGORY" "VM Disks" "qm list" "$RUN_TS" "No VMs found"; fi
    for id in "${VMIDS[@]}"; do
        run_capture "qm-config-${id}" "qm config ${id}" qm config "$id"
        if ! run_ready "VMID $id" "$CATEGORY" "VM Disk Config" "qm config ${id}"; then continue; fi
        awk -F': ' '$1 ~ /^(ide|sata|scsi|virtio|efidisk|tpmstate)[0-9]+$/ {print $1 "\t" substr($0,index($0,": ")+2)}' "$RUN_STDOUT" |
        while IFS=$'\t' read -r disk spec; do
            first="${spec%%,*}"; storage="${first%%:*}"; volume="${first#*:}"
            emit_record "VMID $id" "$CATEGORY" "Disk $disk / Storage" "$storage" "qm config <VMID>" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
            emit_record "VMID $id" "$CATEGORY" "Disk $disk / Volume" "$volume" "qm config <VMID>" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
            IFS=',' read -ra parts <<< "$spec"
            for part in "${parts[@]:1}"; do
                [[ "$part" == *=* ]] || continue
                key="${part%%=*}"; val="${part#*=}"
                emit_record "VMID $id" "$CATEGORY" "Disk $disk / $key" "$val" "qm config <VMID>" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
            done
        done
    done
fi

run_capture "node-storage-json" "pvesh get /nodes/<NODE>/storage --output-format json" pvesh get "/nodes/${NODE}/storage" --output-format json
if run_ready "$NODE" "$CATEGORY" "Thin/Features" "pvesh get /nodes/<NODE>/storage --output-format json"; then
    json_array_fields "$RUN_STDOUT" . storage type active enabled shared total used avail used_fraction content | while IFS=$'\t' read -r storage field value; do
        emit_record "${NODE} / Storage ${storage}" "$CATEGORY" "Node Storage / $field" "$value" "pvesh get /nodes/<NODE>/storage" "$RUN_TS" "Read-only; Evidence=${RUN_EVIDENCE_REL}"
    done
fi
finish_collector
