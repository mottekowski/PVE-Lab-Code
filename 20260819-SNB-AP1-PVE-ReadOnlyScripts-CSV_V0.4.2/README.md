# AP1 PVE/Ceph Read-only Cluster Collector - V0.4.2

## Zweck

Dieses Paket dient zur technischen AP1-Datenerfassung auf einem Proxmox-VE-Cluster mit integriertem Ceph. V0.4.2 ist eine reine Quality-/Usability-Version auf Basis der unveränderten V0.4.1-Collection-Architektur.

Wichtig: Die Collector führen ausschließlich die vorgesehenen Read-only-Abfragen aus. Rot markierte bzw. schreibende Befehle aus dem AP1-Cheat-Sheet bleiben ausgeschlossen. Insbesondere werden `pvecm expected`, `pvesm status --verbose` und `rados bench ... write` nicht ausgeführt.

## Zentrales Ausführungsmodell

`00-ap1-cluster-collect.sh` wird auf **einem PVE-Node als Coordinator** gestartet.

1. Cluster-Nodes werden mit `pvesh get /nodes --output-format json` ermittelt.
2. Der lokale Node wird direkt abgefragt.
3. Remote-Nodes werden über nicht-interaktives SSH abgefragt.
4. Die einzelnen Collector-Skripte selbst bleiben auf dem Coordinator. Sie werden nicht auf die Remote-Nodes kopiert.
5. Auch CSV-OUTPUT, Evidence und Run-Logs werden ausschließlich auf dem Coordinator geschrieben.
6. Nach der Erfassung werden die einzelnen CSVs automatisch zu konsolidierten CSV-Dateien zusammengeführt.

Damit bleibt die technische Ausführung auf den PVE-Nodes read-only; Remote-Dateien oder temporäre Collector-Dateien werden nicht angelegt.

## Voraussetzungen

- Ausführung als Benutzer mit den notwendigen Leserechten für PVE/Ceph; in der Praxis typischerweise `root`.
- SSH vom Coordinator zu allen anderen PVE-Nodes muss nicht-interaktiv funktionieren.
- Hostnamen der von PVE gemeldeten Cluster-Nodes müssen vom Coordinator per SSH erreichbar sein.
- Perl mit `JSON::PP` wird für die JSON-Normalisierung verwendet.
- Die Ceph-Collector müssen auf dem ausgewählten Ceph-Node die notwendigen Ceph-Leserechte besitzen.

Der Collector konfiguriert **keine** SSH-Keys, `known_hosts` oder Berechtigungen automatisch.

## Aufruf

```bash
chmod +x ./*.sh ./lib/*.sh
./00-ap1-cluster-collect.sh
```

Optional:

```bash
./00-ap1-cluster-collect.sh \
  --run-id 20260819_1440 \
  --timezone Europe/Berlin \
  --ssh-user root \
  --ceph-node pve01
```

`--run-id` folgt bewusst dem Format `YYYYMMDD_HHMM`. Wird keine Run-ID angegeben, wird sie in der mit `--timezone` bzw. `AP1_TIMEZONE` festgelegten IANA-Zeitzone erzeugt. Default ist `Europe/Berlin`. Alle CSV-Zeitstempel werden als ISO 8601 mit explizitem UTC-Offset geschrieben, z. B. `2026-08-19T16:19:00+02:00`.

## Ausführungsumfang

### Auf allen ONLINE PVE-Nodes

- `01-pve-info.sh`
- `02-pve-cluster.sh`
- `03-pve-ha.sh`
- `04-pve-storage.sh`
- `05-pve-network.sh`
- `06-pve-ops.sh`
- `11-ceph-perf.sh`

Diese Skripte enthalten node-lokale Informationen bzw. eine node-lokale Sicht, z. B. Version/Kernel/NTP, Corosync-Linkstatus, lokales VM/CT-Inventar, Storage-Sicht, Netzwerk, System-Logs oder Interface-Counter.

### Einmal auf dem ausgewählten Ceph-Node

- `07-ceph-status.sh`
- `08-ceph-topology.sh`
- `09-ceph-pools.sh`
- `10-ceph-capacity.sh`
- `12-ceph-recovery.sh`

Diese Abfragen sind clusterweit.


## V0.4.1 Bugfix: vollstaendige Multi-Host-Abdeckung

OpenSSH liest standardmaessig von `stdin`. In V0.4 konnte dadurch eine Remote-SSH-Verbindung innerhalb der Node-Schleife die noch nicht verarbeiteten Zeilen der internen Node-Liste konsumieren. Das beobachtete Fehlerbild war: `pve01 pve02 pve03` wurden entdeckt, aber nach der Remote-Ausfuehrung auf `pve02` wurde `pve03` nicht mehr verarbeitet.

V0.4.1 verhindert dies dreifach:

- alle SSH-Aufrufe verwenden `ssh -n`,
- Collector-Prozesse werden mit `stdin=/dev/null` gestartet,
- ein Coverage-Gate prueft fuer jeden ONLINE-Node alle erwarteten All-Host-Outputs (01-06 und 11).

Bei drei ONLINE-Nodes muessen damit 21 All-Host-CSV-Dateien entstehen. Fehlt eine erwartete Datei, endet der Orchestrator mit einem Fehler und meldet `COVERAGE_MISSING` im Execution Summary.


## V0.4.2 Quality-/Usability-Korrekturen

Die Collection-Architektur, die All-Host-/Cluster-Once-Zuordnung, die zentrale Ablage und die Merge-Logik sind gegenüber V0.4.1 unverändert. V0.4.2 ändert ausschließlich:

- fehlendes `lldpcli` wird als `OPTIONAL_TOOL_NOT_INSTALLED` statt als Collector-Fehler ausgewiesen,
- identische Package-Zeilen aus `pveversion -v` werden dedupliziert (behebt u. a. das beobachtete `proxmox-kernel-helper`-Duplikat),
- der `ceph tell osd.* perf dump`-Ausschnitt wird eindeutig als `Daemon Perf Sample` mit Erfassungs-Host gekennzeichnet; Wiederholungen über mehrere Hosts bleiben als Evidence nachvollziehbar,
- Run-ID und CSV-Zeitstempel verwenden eine explizite IANA-Zeitzone; Default ist `Europe/Berlin`, der ISO-Zeitstempel enthält den UTC-Offset.

## OUTPUT-Nomenklatur

Die V0.4.2-Nomenklatur lautet:

```text
YYYYMMDD_HHMM_Nummer_Host_Kategorie_Was.csv
```

Beispiele:

```text
20260819_1440_01_pve01_ProxMoxCluster_PVEInfo.csv
20260819_1440_05_pve02_NetworkPlatform_PVENetwork.csv
20260819_1440_07_pve01_CephCluster_CephStatus.csv
20260819_1440_11_pve03_CephCluster_CephPerf.csv
```

Die Dateien werden unter folgendem relativen Pfad gesammelt:

```text
outputfiles/YYYYMMDD_HHMM/
```

## Konsolidierte CSVs / spätere Sheets

Nach dem Lauf erstellt `90-ap1-merge.sh` unter

```text
mergedfiles/YYYYMMDD_HHMM/
```

vier Dateien:

```text
YYYYMMDD_HHMM_ProxMoxCluster_AllHosts.csv
YYYYMMDD_HHMM_NetworkPlatform_AllHosts.csv
YYYYMMDD_HHMM_CephCluster_AllHosts.csv
YYYYMMDD_HHMM_AP1_AllHosts_Review.csv
```

Die ersten drei Dateien entsprechen direkt den jeweiligen Acht-Spalten-Strukturen des AP1-Templates und sind die bevorzugten Importquellen für einzelne Worksheets.

`AP1_AllHosts_Review.csv` ist ein zusätzliches **Ein-Sheet-Review**. Es verwendet ebenfalls acht Spalten, benennt Spalte 2 jedoch generisch als `Kategorie/Segment`, damit ProxMox-, Ceph- und Network-Zeilen gemeinsam geprüft und gefiltert werden können. Diese Datei ist für Review/Analyse gedacht, nicht als 1:1-Import in einen einzelnen bestehenden Template-Reiter.

Es erfolgt bewusst **keine fachliche Deduplizierung** clusterweiter Werte. Wenn ein All-Host-Collector auf mehreren Nodes dieselbe clusterweite Information liefert, bleibt die jeweilige Node-Sicht zur Evidence/Nachvollziehbarkeit erhalten.

## Struktur der Data-Capture CSVs

`ProxMoxCluster` und `CephCluster`:

```text
Node/Scope;Kategorie;Parameter;Wert;Befehl/Quelle;Zeitstempel;Validiert (Y/N);Kommentar
```

`NetworkPlatform`:

```text
Node/Standort;Segment;Parameter;Wert;Befehl/Quelle;Zeitstempel;Validiert (Y/N);Kommentar
```

CSV-Format:

- UTF-8
- Semikolon als Trennzeichen
- alle Felder in Anführungszeichen
- ein atomarer Parameter/Wert pro Zeile
- keine mehrzeiligen CLI-Blöcke im Data Capture
- `Validiert (Y/N)` initial `N`

## Evidence und Run-Logs

Raw-Evidence:

```text
evidencefiles/YYYYMMDD_HHMM/<host>/<script>/<command>.txt
```

Operative Ausführungslogs:

```text
runlogs/YYYYMMDD_HHMM/
```

`YYYYMMDD_HHMM_ExecutionSummary.csv` zeigt je Node/Collector den Orchestrierungsstatus und den erzeugten OUTPUT-Pfad.

## Fehlerverhalten

- Offline Nodes werden in der Node-Inventur erfasst, aber nicht abgefragt.
- Fehlt SSH zu einem Online-Node, wird dieser im Execution Summary als `SKIPPED_SSH_UNAVAILABLE` dokumentiert.
- Collector-interne Abfragefehler werden weiterhin als `Collector Status / ... = ERROR` im jeweiligen Data-Capture-CSV dokumentiert.
- Der Orchestrator beendet sich mit Exit-Code `2`, wenn Node-/SSH-/Ausführungsprobleme vorliegen; bereits erzeugte Outputs bleiben erhalten.

## Einzelne Collector manuell ausführen

Ein Collector kann weiterhin direkt auf dem lokalen Node gestartet werden:

```bash
./05-pve-network.sh
```

Oder vom Coordinator gezielt gegen einen Remote-Node:

```bash
AP1_TARGET_HOST=pve02 AP1_RUN_ID=20260819_1440 ./05-pve-network.sh
```

Die CSV-/Evidence-Dateien bleiben auch in diesem Fall auf dem Coordinator.
