#!/usr/bin/env bash
# Merge AP1 V0.4.1 per-host CSV files into sheet-oriented CSVs and one generic review CSV.

set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUN_ID="${1:-${AP1_RUN_ID:-}}"
if [[ -z "$RUN_ID" ]]; then
    RUN_ID="$(find "${SCRIPT_DIR}/outputfiles" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n1)"
fi
if [[ -z "$RUN_ID" || ! "$RUN_ID" =~ ^[0-9]{8}_[0-9]{4}$ ]]; then
    printf 'Usage: %s YYYYMMDD_HHMM\n' "$0" >&2
    exit 64
fi

SRC="${SCRIPT_DIR}/outputfiles/${RUN_ID}"
DST="${SCRIPT_DIR}/mergedfiles/${RUN_ID}"
mkdir -p "$DST"

PVE_HEADER='"Node/Scope";"Kategorie";"Parameter";"Wert";"Befehl/Quelle";"Zeitstempel";"Validiert (Y/N)";"Kommentar"'
NET_HEADER='"Node/Standort";"Segment";"Parameter";"Wert";"Befehl/Quelle";"Zeitstempel";"Validiert (Y/N)";"Kommentar"'
MASTER_HEADER='"Node/Scope";"Kategorie/Segment";"Parameter";"Wert";"Befehl/Quelle";"Zeitstempel";"Validiert (Y/N)";"Kommentar"'

merge_group() {
    local token="$1" header="$2" outfile="$3"
    local -a files=()
    mapfile -t files < <(find "$SRC" -maxdepth 1 -type f -name "${RUN_ID}_*_*_${token}_*.csv" -print | sort)
    printf '%s\n' "$header" > "$outfile"
    local f h
    for f in "${files[@]}"; do
        h="$(head -n1 "$f" | tr -d '\r')"
        if [[ "$h" != "$header" ]]; then
            printf 'Header mismatch, refusing merge: %s\n' "$f" >&2
            return 2
        fi
        tail -n +2 "$f" >> "$outfile"
    done
    printf 'Merged %d file(s): %s\n' "${#files[@]}" "$outfile"
}

PVE_OUT="${DST}/${RUN_ID}_ProxMoxCluster_AllHosts.csv"
NET_OUT="${DST}/${RUN_ID}_NetworkPlatform_AllHosts.csv"
CEPH_OUT="${DST}/${RUN_ID}_CephCluster_AllHosts.csv"
MASTER_OUT="${DST}/${RUN_ID}_AP1_AllHosts_Review.csv"

merge_group "ProxMoxCluster" "$PVE_HEADER" "$PVE_OUT"
merge_group "NetworkPlatform" "$NET_HEADER" "$NET_OUT"
merge_group "CephCluster" "$PVE_HEADER" "$CEPH_OUT"

# Generic one-sheet review. It deliberately keeps the same eight-column structure.
# Column 2 is named Kategorie/Segment because Network_Platform uses Segment there.
printf '%s\n' "$MASTER_HEADER" > "$MASTER_OUT"
for f in "$PVE_OUT" "$NET_OUT" "$CEPH_OUT"; do
    tail -n +2 "$f" >> "$MASTER_OUT"
done
printf 'Created one-sheet review CSV: %s\n' "$MASTER_OUT"
