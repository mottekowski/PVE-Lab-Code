# Quality Check - AP1 Collector V0.4.1

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

Für das erzeugte Paket wurden durchgeführt:

- `bash -n` für alle 15 Bash-Dateien (14 Top-Level-Skripte inkl. Orchestrator/Merge + Common Library): erfolgreich.
- `perl -c lib/ap1-json.pl`: erfolgreich.
- Remote-Wrapper-Smoke-Test mit einem simulierten SSH-Ziel: OUTPUT wurde unter dem Target-Hostnamen auf dem Coordinator erzeugt.
- SSH-Quoting-Test mit literalem Wildcard-Argument `osd.*` und `bash -c`: erfolgreich.
- Merge-Test mit synthetischen ProxMox-, Network- und Ceph-CSVs: drei sheet-kompatible Dateien plus `AP1_AllHosts_Review` erzeugt.
- Orchestrator-Smoke-Test mit drei simulierten ONLINE PVE-Nodes: 27 erwartete Einzel-CSVs (`00` + 7 x 3 All-Host + 5 Cluster-Once) und vier Merge-CSVs erzeugt; Exit-Code 0.

Diese Build-Tests validieren Orchestrierung, Dateinamen, zentrale Ablage und Merge-Logik. Die echte PVE/Ceph-Ausführung und die inhaltliche Prüfung der erzeugten Werte erfolgt anschließend in der vorgesehenen Testumgebung.


## V0.4.1 Orchestrierungs-Regressionstest

- Drei ONLINE-Nodes muessen als `pve01`, `pve02`, `pve03` entdeckt werden.
- Fuer jeden Node muessen die Collector 01-06 und 11 ausgefuehrt werden.
- Erwartete Anzahl All-Host-CSV bei drei Nodes: 21.
- Der Coverage-Gate bricht den Lauf ab, wenn auch nur eine erwartete Host/Collector-Datei fehlt.
- SSH darf den Input des Node-Loops nicht lesen (`ssh -n` / `stdin=/dev/null`).
