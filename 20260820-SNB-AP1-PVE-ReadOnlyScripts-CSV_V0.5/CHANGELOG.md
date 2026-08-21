# Changelog

## V0.5 - 2026-08-20

- Additiv: neuer Entry Point `00-ap1-v05-collect.sh`; bestehende V0.4.2-Scripts bleiben byte-identisch.
- Neu: `13-pve-permissions.sh` fuer Permissions/Roles/Groups/ACLs/API-Token-Metadaten als **CORE**.
- Neu: `14-pve-ha-core.sh` fuer vertiefte HA-Erfassung als **ARCHITECTURE_CRITICAL / CORE**.
- Neu: `15-pve-ha-node.sh` fuer node-lokale Watchdog-/Fencing-Baseline auf allen ONLINE Nodes.
- Permissions: keine Secrets/Credentials; freie Kommentare und personenbezogene User-Metadaten werden nicht in Evidence/CSV uebernommen.
- HA: robuste Statuswerte fuer nicht konfigurierte bzw. versionsbedingt nicht vorhandene Features; keine Failover-/Fencing-/Watchdog-Tests.
- HA: Workload-Korrelation ueber VMID/CTID ohne Spiegelung vollstaendiger Guest-Konfigurationen.
- XLSX: keine Schemaaenderung; neue 13/14/15-CSVs werden ueber die bestehende Merge-Logik automatisch in `ProxMoxCluster_AllHosts.csv` aufgenommen und in `ProxMox_Cluster` importiert.
- Kein SDN-Collector und keine neue SDN-CSV.
- Bestehende V0.4.2-Quality-Fixes und Orchestrierungsarchitektur bleiben unveraendert.

## V0.4.2 - 2026-08-19

- Quality: fehlendes optionales `lldpcli` wird als `OPTIONAL_TOOL_NOT_INSTALLED` statt als `ERROR` normalisiert.
- Quality: identische `pveversion -v` Package/Version-Zeilen werden dedupliziert; behebt das beobachtete `proxmox-kernel-helper`-Duplikat.
- Usability: Ceph Daemon Perf wird explizit als `Daemon Perf Sample` inklusive Erfassungs-Host und Sample-OSD gekennzeichnet.
- Auditability: explizite IANA-Zeitzone fuer automatische Run-ID und ISO-8601-Zeitstempel; Default `Europe/Berlin`.
- Keine Aenderung an Orchestrierung, All-Host-/Cluster-Once-Zuordnung, Ablagestruktur oder Merge-Architektur.

## V0.4.1 - 2026-08-19

- Bugfix: SSH sessions use `-n` so they cannot consume the node-list input stream of the coordinator loop.
- Bugfix: child collectors are started with `stdin` redirected from `/dev/null`.
- Added coverage gate: every ONLINE node must produce all seven expected all-host CSVs (01-06, 11); otherwise the run exits with an orchestration error.

## V0.4 - 2026-08-19

- Zentralen Multi-Host-Orchestrator `00-ap1-cluster-collect.sh` ergaenzt.
- Automatische PVE-Node-Erkennung ueber `pvesh get /nodes --output-format json`.
- `01-06` und `11` werden auf allen ONLINE PVE-Nodes ausgefuehrt.
- `07-10` und `12` werden einmal auf einem waehlbaren Ceph-Node ausgefuehrt.
- Remote-Kommandos werden ueber SSH ausgefuehrt; CSV, Evidence und temporaere Verarbeitung bleiben vollstaendig auf dem Coordinator.
- OUTPUT-Namen auf `YYYYMMDD_HHMM_Nummer_Host_Kategorie_Was.csv` umgestellt.
- `90-ap1-merge.sh` erstellt drei sheet-kompatible All-Hosts-CSVs und ein gemeinsames Ein-Sheet-Review.

## V0.3 - 2026-08-19

- PVE-9-HA-Rules beruecksichtigt; Legacy-HA-Groups als Read-only-Fallback.
- Interface-Erkennung korrigiert; `bonding_masters` nicht als NIC behandelt.
- Ceph Nearfull/Full aus `ceph osd dump` normalisiert.
- Daemon-Perf-Dump generischer normalisiert.

## V0.2

- Gemeinsames Parameter/Wert-Normalisierungsprinzip eingefuehrt.
- Raw CLI/JSON-Ausgaben in separate Evidence-Dateien ausgelagert.
