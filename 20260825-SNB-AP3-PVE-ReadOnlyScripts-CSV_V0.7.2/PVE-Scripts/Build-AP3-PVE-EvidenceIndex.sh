#!/usr/bin/env bash
# PVE-seitiger Evidence Index fuer AP3 V0.7.2.
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUN_ID="${1:-${AP3_RUN_ID:-}}"; [[ -n "$RUN_ID" ]] || { echo "Usage: $0 <Run-ID>" >&2; exit 64; }
RAW_ROOT="${AP3_OUTPUT_ROOT:-${SCRIPT_DIR}/PVE-Out}"; MERGED_ROOT="${AP3_MERGED_ROOT:-${SCRIPT_DIR}/PVE-Merged}"
RAW="${RAW_ROOT}/${RUN_ID}"; MERGED="${MERGED_ROOT}/${RUN_ID}"; OUT="${MERGED}/${RUN_ID}_Evidence_Index.csv"; mkdir -p "$MERGED"
q(){ local s="${1-}"; s="${s//$'\r'/}"; s="${s//$'\n'/ | }"; s="${s//\"/\"\"}"; printf '"%s"' "$s"; }
sheet(){ case "$1" in AP3-31-*|AP3-32-*|AP3-33-*|*_PBS_Anbindung_AllTargets.csv) echo PBS_Anbindung;; AP3-51-*|*_Policies_Retention_AllTargets.csv) echo Policies_Retention;; *_PBS_Storage_AllTargets.csv) echo PBS_Storage;; *_RTO_RPO_AllTargets.csv) echo RTO_RPO;; *_AP3_PVE_AllTargets_Review.csv) echo Review;; *_AP3_PBS_Scope.csv|*_MergeSummary.csv) echo Collector;; *) echo n/a;; esac; }
{
printf '"Evidence-ID";"Typ (Log/Export/Screenshot)";"Beschreibung";"Quelle (System)";"Befehl/Path/URL";"Zeitstempel";"Ablageort/Link";"Referenz (Sheet/Item)";"Hash/Checksum";"Notizen"\n'
i=1
while IFS= read -r f; do [[ -f "$f" && "$f" != "$OUT" ]] || continue; b="$(basename "$f")"; id="$(printf 'AP3-PVE-E-%03d' "$i")"; hash="$(sha256sum "$f"|awk '{print $1}')"; ts="$(date --iso-8601=seconds -r "$f" 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"; ref="$(sheet "$b")"; q "$id";printf ';';q Export;printf ';';q "AP3 PVE Artefakt $b";printf ';';q "PVE / ${AP3_COLLECTOR_NODE:-$(hostname -s)}";printf ';';q "$b";printf ';';q "$ts";printf ';';q "$f";printf ';';q "$ref";printf ';';q "sha256:$hash";printf ';';q 'Environment=PVE; Read-only; Validiert=N';printf '\n'; i=$((i+1)); done < <(find "$RAW" "$MERGED" -maxdepth 1 -type f \( -name '*.csv' -o -name '*.log' \) -print 2>/dev/null | sort)
} > "$OUT"
printf '%s\n' "$OUT"
