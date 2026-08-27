#!/usr/bin/env bash
# AP3 V0.7.2 - Hilfsfunktionen zur lesbaren Normalisierung von
# Proxmox/PBS-CLI-Tabellen mit Unicode-Rahmenzeichen.
# Keine Remote-Zugriffe, keine Systemaenderungen.

AP3_TABLE_SEP=$'\x1f'

# Wandelt eine Proxmox/PBS-Box-Tabelle in US-separierte Zeilen um.
# Die erste ausgegebene Zeile ist die Tabellenkopfzeile, danach folgen Datenzeilen.
# Beispiel: "│ name │ path │" -> "name<US>path"
ap3_box_table_usv_rows() {
  awk -F '│' -v sep="$(printf '\037')" '
    function trim(s) {
      gsub(/^[[:space:]]+/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      return s
    }
    index($0, "│") {
      out=""; count=0
      for (i=2; i<NF; i++) {
        cell=trim($i)
        if (count > 0) out=out sep
        out=out cell
        count++
      }
      if (count > 0) print out
    }
  '
}

# Gibt pro Datenzeile einen kompakten Datensatz aus:
# <row><US><first-cell><US><header1=value1; header2=value2; ...>
# Leere Werte werden weggelassen. Rueckgabecode 1 = keine erkennbare Box-Tabelle.
ap3_box_table_records() {
  local input="${1-}"
  local -a rows headers cells
  local i j first summary pair

  mapfile -t rows < <(printf '%s\n' "$input" | ap3_box_table_usv_rows)
  (( ${#rows[@]} >= 2 )) || return 1

  IFS="$AP3_TABLE_SEP" read -r -a headers <<< "${rows[0]}"
  (( ${#headers[@]} > 0 )) || return 1

  for ((i=1; i<${#rows[@]}; i++)); do
    IFS="$AP3_TABLE_SEP" read -r -a cells <<< "${rows[$i]}"
    first="${cells[0]-}"
    summary=""
    for ((j=0; j<${#headers[@]}; j++)); do
      [[ -n "${cells[$j]-}" ]] || continue
      pair="${headers[$j]}=${cells[$j]}"
      if [[ -n "$summary" ]]; then summary+="; "; fi
      summary+="$pair"
    done
    [[ -n "$summary" ]] || continue
    printf '%s%s%s%s%s\n' "$i" "$AP3_TABLE_SEP" "$first" "$AP3_TABLE_SEP" "$summary"
  done
}

# Gibt fuer typische zweispaltige Name/Value-Tabellen die Datenzeilen als
# <name><US><value> aus. Rueckgabecode 1 = keine erkennbare zweispaltige Tabelle.
ap3_box_table_key_values() {
  local input="${1-}"
  local -a rows headers cells
  local i

  mapfile -t rows < <(printf '%s\n' "$input" | ap3_box_table_usv_rows)
  (( ${#rows[@]} >= 2 )) || return 1
  IFS="$AP3_TABLE_SEP" read -r -a headers <<< "${rows[0]}"
  (( ${#headers[@]} >= 2 )) || return 1

  for ((i=1; i<${#rows[@]}; i++)); do
    IFS="$AP3_TABLE_SEP" read -r -a cells <<< "${rows[$i]}"
    [[ -n "${cells[0]-}" ]] || continue
    printf '%s%s%s\n' "${cells[0]}" "$AP3_TABLE_SEP" "${cells[1]-}"
  done
}
