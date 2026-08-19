# Changelog

## V0.4.1 - 2026-08-19

- Bugfix: SSH sessions use `-n` so they cannot consume the node-list input stream of the coordinator loop.
- Bugfix: child collectors are started with `stdin` redirected from `/dev/null`.
- Added coverage gate: every ONLINE node must produce all seven expected all-host CSVs (01-06, 11); otherwise the run exits with an orchestration error.
- Fix addresses the observed case where `pve03` was discovered but silently skipped after remote collection on `pve02`.

## V0.4 - 2026-08-19

- Zentralen Multi-Host-Orchestrator `00-ap1-cluster-collect.sh` ergänzt.
- Automatische PVE-Node-Erkennung über `pvesh get /nodes --output-format json`.
- `01-06` und `11` werden auf allen ONLINE PVE-Nodes ausgeführt.
- `07-10` und `12` werden einmal auf einem wählbaren Ceph-Node ausgeführt.
- Remote-Kommandos werden über SSH ausgeführt; CSV, Evidence und temporäre Verarbeitung bleiben vollständig auf dem Coordinator.
- OUTPUT-Namen auf `YYYYMMDD_HHMM_Nummer_Host_Kategorie_Was.csv` umgestellt.
- Run-basierte Ablage unter `outputfiles`, `evidencefiles`, `runlogs` und `mergedfiles` ergänzt.
- `90-ap1-merge.sh` erstellt drei sheet-kompatible All-Hosts-CSVs und ein gemeinsames Ein-Sheet-Review.
- Interface-Discovery in `11-ceph-perf.sh` für Remote-Target-Ausführung korrigiert.

## V0.3 - 2026-08-19

- PVE-9-HA-Rules berücksichtigt; Legacy-HA-Groups als Read-only-Fallback.
- Interface-Erkennung korrigiert; `bonding_masters` nicht als NIC behandelt.
- Ceph Nearfull/Full aus `ceph osd dump` normalisiert.
- Daemon-Perf-Dump generischer normalisiert.

## V0.2

- Gemeinsames Parameter/Wert-Normalisierungsprinzip eingeführt.
- Raw CLI/JSON-Ausgaben in separate Evidence-Dateien ausgelagert.
