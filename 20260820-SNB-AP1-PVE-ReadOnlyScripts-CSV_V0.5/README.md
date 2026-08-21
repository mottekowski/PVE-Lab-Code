# AP1 PVE/Ceph Read-only Cluster Collector - V0.5

## Zweck

V0.5 erweitert das bestehende AP1-Collector-Paket gezielt um zwei CORE-Bereiche fuer das PVE/Ceph Stretch Readiness Assessment:

1. **Permissions / Roles / Groups / ACLs / API-Token-Metadaten**
2. **HA Architecture Critical / CORE** mit vertieftem HA-Status, HA-Ressourcen, Placement Rules/Legacy Groups, Workload-Korrelation sowie node-lokalem Watchdog-/Fencing-Status

Die bestehende V0.4.2-Collection-Architektur, die vorhandenen Collector `00-12`, `90-ap1-merge.sh` sowie die gemeinsame Library/JSON-Helfer bleiben **byte-identisch und unveraendert**. V0.5 ist ausschliesslich additiv.

Die Collector fuehren nur Read-only-/Statusabfragen aus. Es werden keine ACLs, Rollen, Benutzer, Tokens, HA-Ressourcen, Watchdogs, Quorum-Werte oder sonstige produktive Einstellungen veraendert.

## Neue V0.5-Dateien

```text
00-ap1-v05-collect.sh    Additiver V0.5-Orchestrator/Entry Point
13-pve-permissions.sh   Permissions CORE, clusterweit einmal
14-pve-ha-core.sh       HA Architecture Critical CORE, clusterweit einmal
15-pve-ha-node.sh       HA Watchdog/Fencing Baseline, auf allen ONLINE Nodes
V0.5_EXTENSION_MAPPING.md
BASE_SCRIPT_INTEGRITY.md
```

## Aufruf

V0.5 wird ueber den neuen Entry Point gestartet:

```bash
chmod +x ./*.sh ./lib/*.sh
sudo ./00-ap1-v05-collect.sh
```

Optional:

```bash
sudo ./00-ap1-v05-collect.sh \
  --run-id 20260820_1200 \
  --timezone Europe/Berlin \
  --ssh-user root \
  --ceph-node pve01
```

Der neue Wrapper fuehrt zuerst den bestehenden `00-ap1-cluster-collect.sh` **unveraendert** mit `--no-merge` aus, ergaenzt danach die V0.5-Collector und startet abschliessend den bestehenden `90-ap1-merge.sh` **unveraendert**.

## Ausfuehrungsumfang

### Bestehende V0.4.2-Basis - unveraendert

Auf allen ONLINE PVE-Nodes:

```text
01  PVE Info
02  PVE Cluster/Corosync
03  HA Basis
04  PVE Storage
05  PVE Network
06  PVE Ops/Auth/Backup
11  Ceph Perf / node-lokale Network Counter
```

Clusterweit einmal auf dem ausgewaehlten Ceph-Node:

```text
07  Ceph Status
08  Ceph Topology
09  Ceph Pools
10  Ceph Capacity
12  Ceph Recovery
```

### Neue V0.5-Ergaenzungen

Clusterweit einmal auf dem Coordinator:

```text
13  Permissions / Roles / Groups / ACLs / API-Token-Metadaten
14  HA Architecture Critical / CORE
```

Auf allen ONLINE PVE-Nodes:

```text
15  HA Node / Watchdog / Fencing Baseline
```

## Permissions - CORE

`13-pve-permissions.sh` erfasst technisch verwertbare, read-only Informationen fuer die spaetere Korrelation:

```text
Principal -> Realm -> Role -> Path -> Propagate
```

Erfasst werden:

- Roles mit Role-ID, Privileges und Built-in/Custom-Kennzeichnung soweit vom API-Feld `special` ableitbar
- Groups mit Group-ID und Member-Zuordnung
- ACLs mit Principal, Principal Type, Realm, Role, Path und Propagate
- API-Token-Metadaten: User-ID, Token-ID, Privilege Separation und Expire, soweit vorhanden

Die bestehende User-/Realm-Erfassung in `06-pve-ops.sh` wird nicht dupliziert oder veraendert.

### Sicherheitsgrenzen

V0.5 exportiert aus dem Permissions-Collector insbesondere **nicht**:

- Token Secrets
- Passwoerter
- LDAP Bind Passwords
- Private Keys
- API Secrets
- Recovery Keys
- freie User-/Group-/Token-Kommentare
- E-Mail-/Vor-/Nachnamen aus der Userliste

Die Scripts erzeugen keine automatische Bewertung wie `SECURE`, `INSECURE`, `COMPLIANT` oder `NON_COMPLIANT`.

## HA - ARCHITECTURE_CRITICAL / CORE

`14-pve-ha-core.sh` ergaenzt die bestehende HA-Basiserfassung aus Script 03. Erfasst werden unter anderem:

- HA Current Status / Quorum-/CRM-/LRM-Sicht
- HA Manager Status
- HA Resources und stretch-relevante Resource-Parameter
- PVE 9+ HA Rules mit versionsrobuster Legacy-HA-Group-Behandlung
- Workload-Korrelation ueber VMID/CTID: aktueller Node, Laufstatus und HA-managed Yes/No

Gueltige Zustandswerte sind unter anderem:

```text
NO_HA_RESOURCES_CONFIGURED
NO_HA_RULES_CONFIGURED
NO_HA_GROUPS_CONFIGURED
FEATURE_NOT_AVAILABLE_IN_PVE_VERSION
NO_DATA
UNAVAILABLE
```

`15-pve-ha-node.sh` erfasst auf jedem Online-Node ausschliesslich passive Statusinformationen zu:

- `pve-ha-lrm`
- `pve-ha-crm`
- `watchdog-mux`
- konfiguriertem `WATCHDOG_MODULE`
- `/sys/class/watchdog/*` Identity/State/Nowayout/Timeout

`/dev/watchdog` wird **nie** geoeffnet. Es wird kein Watchdog-Test und kein Fencing ausgeloest.

## Kein SDN-Collector

V0.5 fuegt keinen SDN-Collector und keine SDN-CSV hinzu. Die bestehende Netzwerkaufnahme bleibt unveraendert.

## OUTPUT-Nomenklatur

Die bestehende Nomenklatur bleibt unveraendert:

```text
YYYYMMDD_HHMM_Nummer_Host_Kategorie_Was.csv
```

Neue Beispiele:

```text
20260820_1200_13_pve01_ProxMoxCluster_PVEPermissions.csv
20260820_1200_14_pve01_ProxMoxCluster_PVEHACore.csv
20260820_1200_15_pve01_ProxMoxCluster_PVEHANode.csv
20260820_1200_15_pve02_ProxMoxCluster_PVEHANode.csv
```

## XLSX-/Template-Kompatibilitaet

Die V0.5-Erweiterungen verwenden bewusst **keine neuen CSV-Spalten und keinen neuen Worksheet-Typ**.

Alle neuen Daten werden mit exakt dem bestehenden Schema erzeugt:

```text
Node/Scope;Kategorie;Parameter;Wert;Befehl/Quelle;Zeitstempel;Validiert (Y/N);Kommentar
```

Die neuen Dateien 13, 14 und 15 verwenden `ProxMoxCluster` als Dateikategorie. Dadurch werden sie vom bestehenden `90-ap1-merge.sh` automatisch in folgende Importdatei aufgenommen:

```text
mergedfiles/<Run-ID>/<Run-ID>_ProxMoxCluster_AllHosts.csv
```

Diese Datei wird wie bisher in den Template-Reiter **`ProxMox_Cluster`** importiert. Fuer V0.5 sind keine zusaetzlichen XLSX-Spalten und kein neuer Reiter erforderlich.

Weiterhin gilt:

```text
*_ProxMoxCluster_AllHosts.csv   -> ProxMox_Cluster
*_NetworkPlatform_AllHosts.csv  -> Network_Platform
*_CephCluster_AllHosts.csv      -> Ceph_Cluster
```

## Ablage

```text
outputfiles/<Run-ID>/     Einzel-Collector-CSVs
evidencefiles/<Run-ID>/   Raw-Evidence/Command-Ausgaben
runlogs/<Run-ID>/         Execution Summary und Collector-Logs
mergedfiles/<Run-ID>/     Konsolidierte CSVs fuer den XLSX-Import
```

## Erwartung bei einem 3-Node-Testlauf

Bei drei ONLINE PVE-Nodes entstehen aus der unveraenderten Basis 27 Einzel-CSVs. V0.5 ergaenzt:

```text
13 Permissions       1 x clusterweit
14 HA Core           1 x clusterweit
15 HA Node           3 x node-lokal
```

Damit werden bei einem vollstaendigen 3-Node-Lauf **32 Einzel-CSVs** erwartet.

## Testumgebung

Die vorhandene 3-Node-PVE-Testumgebung dient ausschliesslich zur Validierung von Scriptfunktion, PVE-Versionsverhalten, CSV-Format, Output-Qualitaet und XLSX-Importierbarkeit. Aus den dort erfassten Werten sind keine Aussagen ueber die Kundenumgebung abzuleiten.

## Hinweise zur Versionsnummer in geerbten Scripts

Die vorhandenen V0.4.2-Scripts wurden auf ausdrueckliche Vorgabe nicht veraendert. Deshalb koennen deren interne Header/Kommentare weiterhin V0.4.1/V0.4.2 nennen. Der **Paketstand und der neue Entry Point sind V0.5**; die unveraenderten Altdateien sind Bestandteil der rueckwaertskompatiblen Basis.
