#!/usr/bin/env bash
# Gemeinsame CSV-Helfer fuer AP3 V0.7.2.
# Eine CSV-Zeile entspricht einem atomaren Parameter/Wert-Datensatz.
set -u

AP3_DATA_HEADER='"Komponente/Scope";"Kategorie";"Parameter";"Wert";"Befehl/Quelle";"Zeitstempel";"Validiert (Y/N)"'

ap3_iso_ts() {
  date --iso-8601=seconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'
}

ap3_csv_escape() {
  local s="${1-}"
  s="${s//$'\r'/}"
  # Keine unbeabsichtigten multiline CSV-Records. Vollstaendige Raw-Ausgaben gehoeren in Evidence.
  s="${s//$'\n'/ | }"
  s="${s//\"/\"\"}"
  printf '"%s"' "$s"
}

ap3_emit() {
  local scope="$1" category="$2" parameter="$3" value="$4" source="$5" ts="$6"
  ap3_csv_escape "$scope"; printf ';'
  ap3_csv_escape "$category"; printf ';'
  ap3_csv_escape "$parameter"; printf ';'
  ap3_csv_escape "$value"; printf ';'
  ap3_csv_escape "$source"; printf ';'
  ap3_csv_escape "$ts"; printf ';'
  ap3_csv_escape "N"; printf '\n'
}

ap3_safe_name() {
  printf '%s' "${1-}" | tr -c 'A-Za-z0-9._-' '_'
}

ap3_classify_error() {
  local rc="${1:-1}" out="${2-}"
  case "$out" in
    *[Pp]ermission\ denied*|*[Aa]ccess\ denied*|*not\ permitted*|*not\ allowed*|*permission\ check\ failed*|*401*|*403*)
      printf 'PERMISSION_DENIED' ;;
    *unknown\ command*|*Unknown\ command*|*no\ such\ command*|*No\ such\ command*|*unrecognized*|*Usage:*)
      printf 'COMMAND_NOT_SUPPORTED' ;;
    *)
      printf 'COLLECTION_FAILED(rc=%s)' "$rc" ;;
  esac
}
