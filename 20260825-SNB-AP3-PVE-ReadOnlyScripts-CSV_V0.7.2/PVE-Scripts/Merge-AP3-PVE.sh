#!/usr/bin/env bash
# Lokaler PVE-Merge fuer AP3 V0.7.2. Verarbeitet ausschliesslich PVE-Out.
set -euo pipefail
export LC_ALL=C
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ap3-csv.sh"
RUN_ID="${1:-${AP3_RUN_ID:-}}"
RAW_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PVE-Out}"
MERGED_ROOT="${AP3_MERGED_ROOT:-${SCRIPT_DIR}/PVE-Merged}"
[[ -n "$RUN_ID" ]] || RUN_ID="$(find "$RAW_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n1)"
[[ -n "$RUN_ID" ]] || { echo "Usage: $0 <Run-ID>" >&2; exit 64; }
SRC="${RAW_ROOT}/${RUN_ID}"; DST="${MERGED_ROOT}/${RUN_ID}"
[[ -d "$SRC" ]] || { echo "ERROR: PVE-Out nicht gefunden: $SRC" >&2; exit 2; }
mkdir -p "$DST"
SUMMARY="${DST}/${RUN_ID}_PVE_MergeSummary.csv"
printf '"MergedFile";"TargetSheet";"ExpectedSources";"MergedSources";"MissingSources";"Status"\n' > "$SUMMARY"
q(){ local s="${1-}"; s="${s//\"/\"\"}"; printf '"%s"' "$s"; }
summary(){ q "$1";printf ';';q "$2";printf ';';q "$3";printf ';';q "$4";printf ';';q "$5";printf ';';q "$6";printf '\n'; }
merge_sheet(){
  local sheet="$1" outfile="$2"; shift 2; local -a prefixes=("$@") files=() missing=(); local p f h
  printf '%s\n' "$AP3_DATA_HEADER" > "$outfile"
  if (( ${#prefixes[@]} == 0 )); then summary "$(basename "$outfile")" "$sheet" 0 0 "" "NOT_APPLICABLE" >> "$SUMMARY"; return 0; fi
  for p in "${prefixes[@]}"; do
    f="${SRC}/${p}_${RUN_ID}.csv"; [[ -f "$f" ]] || { missing+=("$p"); continue; }
    h="$(head -n1 "$f" | tr -d '\r')"; [[ "$h" == "$AP3_DATA_HEADER" ]] || { echo "Header mismatch: $f" >&2; return 2; }
    files+=("$f"); tail -n +2 "$f" >> "$outfile"
  done
  status=OK; (( ${#missing[@]} > 0 )) && status=PARTIAL; (( ${#files[@]} == 0 )) && status=NO_DATA
  summary "$(basename "$outfile")" "$sheet" "${#prefixes[@]}" "${#files[@]}" "${missing[*]:-}" "$status" >> "$SUMMARY"
}
merge_sheet PBS_Anbindung "${DST}/${RUN_ID}_PBS_Anbindung_AllTargets.csv" AP3-31-PBSNet AP3-32-PBSTLS AP3-33-PBSRepo
merge_sheet PBS_Storage "${DST}/${RUN_ID}_PBS_Storage_AllTargets.csv"
merge_sheet Policies_Retention "${DST}/${RUN_ID}_Policies_Retention_AllTargets.csv" AP3-51-PVEJobs
merge_sheet RTO_RPO "${DST}/${RUN_ID}_RTO_RPO_AllTargets.csv"
MASTER="${DST}/${RUN_ID}_AP3_PVE_AllTargets_Review.csv"; printf '%s\n' "$AP3_DATA_HEADER" > "$MASTER"
for f in "${DST}/${RUN_ID}_PBS_Anbindung_AllTargets.csv" "${DST}/${RUN_ID}_PBS_Storage_AllTargets.csv" "${DST}/${RUN_ID}_Policies_Retention_AllTargets.csv" "${DST}/${RUN_ID}_RTO_RPO_AllTargets.csv"; do tail -n +2 "$f" >> "$MASTER"; done
printf 'PVE-Merge abgeschlossen: %s\n' "$DST"
