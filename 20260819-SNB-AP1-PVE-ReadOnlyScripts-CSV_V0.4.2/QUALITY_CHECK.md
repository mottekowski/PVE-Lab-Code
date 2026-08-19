# Quality Check - AP1 Collector V0.4.2

## Prüfkriterien

- Shell-Syntax aller Bash-Skripte mit `bash -n`
- Perl-Syntax des JSON-Helfers mit `perl -c`
- einheitliche Acht-Spalten-Struktur der Data-Capture CSVs
- Dateinamen nach `YYYYMMDD_HHMM_Nummer_Host_Kategorie_Was.csv`
- Multi-Host-Ausführung ohne Kopieren von Collector-/OUTPUT-Dateien auf Remote-Nodes
- SSH-Quoting für Befehle mit Parametern und Wildcards
- zentraler Run-ID-Pfad für OUTPUT, Evidence und Run-Logs
- Merge mit Header-Validierung
- Ein-Sheet-Review mit acht Spalten
- weiterhin keine rot markierten bzw. schreibenden Analysebefehle

## V0.4.1-spezifische technische Änderung

`run_capture` führt Kommandos abhängig von `AP1_TARGET_HOST` lokal oder via SSH aus. stdout und stderr werden in beiden Fällen auf dem Coordinator erfasst. Das bestehende Normalisierungsverhalten der V0.3-Collector bleibt unverändert.

Die Interface-Erkennung in `11-ceph-perf.sh` wurde ebenfalls auf die Target-Node-Ausführung umgestellt, damit bei Remote-Collection nicht versehentlich `/sys/class/net` des Coordinators ausgewertet wird.


## V0.4.2 Quality-/Usability-Regressionen

Zusätzlich zu den bestehenden V0.4.1-Orchestrierungstests werden geprüft:

- fehlendes `lldpcli` erzeugt `OPTIONAL_TOOL_NOT_INSTALLED` und keine `ERROR`-Zeile,
- identische `pveversion -v` Package/Version-Zeilen werden nur einmal ausgegeben,
- Daemon-Perf-Zeilen tragen `Daemon Perf Sample` und einen Scope `Ceph-Cluster via <host> / Sample <osd>`,
- automatisch erzeugte Run-IDs verwenden `AP1_TIMEZONE`/`--timezone`,
- CSV-/Evidence-Zeitstempel sind ISO 8601 mit explizitem UTC-Offset; Default `Europe/Berlin`.

## Erwartete operative Validierung

Vor dem Kundentermin sollte in der Azure-Testumgebung mindestens geprüft werden:

1. Node Discovery erkennt alle drei Lab-Nodes.
2. SSH-Preflight ist zwischen Coordinator und beiden Remote-Nodes erfolgreich.
3. `01-06` und `11` erzeugen je Online-Node eine eindeutige CSV-Datei.
4. `07-10` und `12` werden nur einmal auf dem festgelegten Ceph-Node erzeugt.
5. Keine OUTPUT-Datei wird auf den Remote-Nodes erzeugt.
6. `mergedfiles/<Run-ID>` enthält drei sheet-kompatible CSVs und die gemeinsame Review-CSV.
7. Jede Data-Capture-Datei besitzt exakt acht Spalten.
8. Collector-ERROR-Zeilen werden im Execution Summary bzw. in der fachlichen Prüfung erkannt.

## Durchgeführte Build-Tests

Für V0.4.2 wurden durchgeführt:

- `bash -n` für alle 15 Bash-Dateien (14 Top-Level-Skripte inkl. Orchestrator/Merge + Common Library): erfolgreich.
- `perl -c lib/ap1-json.pl`: erfolgreich.
- Mock-Test `01-pve-info.sh`: identisches `proxmox-kernel-helper` Package/Version-Paar erscheint genau einmal.
- Mock-Test `05-pve-network.sh`: `lldpcli` Exit-Code 127 wird als `OPTIONAL_TOOL_NOT_INSTALLED` und nicht als `ERROR` ausgegeben.
- Mock-Test `11-ceph-perf.sh`: Daemon-Perf-Zeilen werden als `Daemon Perf Sample` mit `Ceph-Cluster via <host> / Sample <osd>` und `SAMPLE_ONLY` gekennzeichnet.
- Zeitzonen-Test `Europe/Berlin`: CSV-Zeitstempel enthält explizit `+02:00`; Evidence enthält `Timezone: Europe/Berlin`.
- Negativtest ungültige IANA-Zeitzone: Abbruch mit Exit-Code 64 vor der Collection.
- Architektur-Invarianz gegen V0.4.1: `ALL_HOST_SCRIPTS`, `CLUSTER_ONCE_SCRIPTS` und `90-ap1-merge.sh` unverändert; nicht betroffene Collector 02-04, 06-10 und 12 sowie `ap1-json.pl` byte-identisch.

Die V0.4.1-Orchestrierungsarchitektur wurde damit bewusst nicht verändert. Die echte PVE/Ceph-Ausführung und die inhaltliche Prüfung der erzeugten Werte erfolgt anschließend in der vorgesehenen Testumgebung.


## V0.4.1 Orchestrierungs-Regressionstest

- Drei ONLINE-Nodes muessen als `pve01`, `pve02`, `pve03` entdeckt werden.
- Fuer jeden Node muessen die Collector 01-06 und 11 ausgefuehrt werden.
- Erwartete Anzahl All-Host-CSV bei drei Nodes: 21.
- Der Coverage-Gate bricht den Lauf ab, wenn auch nur eine erwartete Host/Collector-Datei fehlt.
- SSH darf den Input des Node-Loops nicht lesen (`ssh -n` / `stdin=/dev/null`).
