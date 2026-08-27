# AP1 PVE/Ceph Read-only Cluster Collector - V0.5.1

## Zweck

V0.5.1 ist ein technischer Bugfix innerhalb des bestehenden AP1 V0.5-Collector-Pakets fuer das PVE/Ceph Stretch Readiness Assessment.

Der fachliche Scope bleibt unveraendert:

- PVE Cluster Core
- Corosync / Quorum
- HA Architecture Critical / Core
- Permissions / Roles / ACLs / Auth
- Backup Jobs
- Ceph Core, CRUSH, Pools, Capacity und Performance-Indikatoren
- VM/CT Inventory
- DC2 Readiness
- bestehende CSV-/Merge-/XLSX-Importlogik

V0.5.1 korrigiert ausschliesslich die Erfassung physischer NIC-Statistiken in `11-ceph-perf.sh`.

## V0.5.1 Bugfix - Physical NIC Statistics

In V0.5 wurde fuer `ethtool -S` noch ein dokumentarischer Interface-Platzhalter in Quelle und CSV-Ausgabe verwendet:

```bash
ethtool -S <IFACE>
```

Zusaetzlich wurde die strukturierte Auswertung mit `head -n 50` gekuerzt. Das war fachlich ungeeignet, weil NIC-Treiber unterschiedliche Counter und Reihenfolgen liefern.

V0.5.1 erkennt physische Netzwerkinterfaces dynamisch ueber:

```text
/sys/class/net/<iface>/device
```

Fuer jedes erkannte physische Interface wird separat ausgefuehrt:

```bash
ethtool -S "$iface"
```

Das Feld `Befehl/Quelle` enthaelt damit den tatsaechlich ausgefuehrten Befehl, z. B.:

```text
ethtool -S eno1
ethtool -S enp5s0f0
```

## Interface Discovery

Als physische ethtool-Ziele gelten Interfaces mit Device-Backing unter `/sys/class/net/<iface>/device`.

Folgende logische Interfaces werden nicht als primaere Ziele fuer `ethtool -S` behandelt:

```text
lo
vmbr*
bond*
tap*
veth*
fwbr*
fwln*
fwpr*
```

Bonds, Bridges und andere logische Interfaces bleiben weiterhin ueber die bestehende Linux-Counter-Erfassung relevant, insbesondere:

```bash
ip -s link
```

Die bestehende `ip -s link`-Logik wurde durch den V0.5.1-Bugfix nicht fachlich erweitert oder redesigned.

## Raw Evidence und strukturierte Auswertung

Die vollstaendige `ethtool -S`-Ausgabe wird je physischem Interface als Raw Evidence abgelegt. Es erfolgt keine Kuerzung mit `head -n 50`.

Fuer die strukturierte CSV-Auswertung werden vorhandene Counter dynamisch gefiltert nach:

```text
err
error
errors
drop
drops
discard
crc
fault
miss
timeout
overrun
carrier
```

Nicht vom Treiber gelieferte Counter werden nicht kuenstlich erzeugt und nicht mit `0` aufgefuellt.

Ein numerischer Wert `0` wird nur ausgegeben, wenn der Counter in der erfolgreichen `ethtool -S`-Ausgabe tatsaechlich enthalten war und dessen Wert `0` betraegt.

## Statuswerte

V0.5.1 unterscheidet folgende Situationen explizit:

| Statuswert | Bedeutung |
|---|---|
| `NO_PHYSICAL_INTERFACES_DETECTED` | Es wurde kein geeignetes physisches Interface erkannt. |
| `INTERFACE_NOT_FOUND` | Das Interface existierte bei der `ethtool`-Abfrage nicht mehr oder wurde nicht gefunden. |
| `ETHTOOL_STATS_NOT_SUPPORTED` | Das Interface bzw. der Treiber unterstuetzt keine `ethtool -S`-Statistiken. |
| `COLLECTION_FAILED` | Die Abfrage ist aus einem anderen Grund fehlgeschlagen. |

Fehlgeschlagene oder nicht unterstuetzte Abfragen werden nicht als numerische Nullwerte ausgegeben.

## CSV-/XLSX-Kompatibilitaet

V0.5.1 fuehrt keine neuen CSV-Spalten und keinen neuen Worksheet-Typ ein.

Das bestehende Acht-Spalten-Schema bleibt unveraendert:

```text
Node/Scope;Kategorie;Parameter;Wert;Befehl/Quelle;Zeitstempel;Validiert (Y/N);Kommentar
```

Der Interface-Kontext wird im bestehenden Modell abgebildet:

```text
Node/Scope     : <Node> / <Interface>
Kategorie      : Performance-Indikatoren
Parameter      : Physical NIC Stats / <Interface> / <Counter>
Wert           : <tatsaechlicher Counterwert oder Statuswert>
Befehl/Quelle  : ethtool -S <Interface>
```

Beispiel:

```text
Node/Scope     : pve01 / eno1
Parameter      : Physical NIC Stats / eno1 / rx_crc_errors
Wert           : 0
Befehl/Quelle  : ethtool -S eno1
```

Die bestehenden Merge- und Importziele bleiben unveraendert:

```text
*_ProxMoxCluster_AllHosts.csv   -> ProxMox_Cluster
*_NetworkPlatform_AllHosts.csv  -> Network_Platform
*_CephCluster_AllHosts.csv      -> Ceph_Cluster
```

## Aufruf

V0.5.1 wird weiterhin ueber den bestehenden Entry Point gestartet:

```bash
chmod +x ./*.sh ./lib/*.sh
sudo ./00-ap1-v05-collect.sh
```

Optional:

```bash
sudo ./00-ap1-v05-collect.sh \
  --run-id 20260825_1200 \
  --timezone Europe/Berlin \
  --ssh-user root \
  --ceph-node pve01
```

## Enthaltene V0.5-Collector

V0.5.1 enthaelt weiterhin die V0.5-Ergaenzungen:

```text
13-pve-permissions.sh   Permissions CORE, clusterweit einmal
14-pve-ha-core.sh       HA Architecture Critical CORE, clusterweit einmal
15-pve-ha-node.sh       HA Watchdog/Fencing Baseline, auf allen ONLINE Nodes
```

Diese Bereiche wurden durch V0.5.1 nicht fachlich erweitert.

## Read-only-Grenzen

Alle Collector bleiben read-only und non-invasive.

Zulaessig im Kontext des V0.5.1-Bugfixes sind nur lesende Abfragen, z. B.:

```bash
ethtool -S "$iface"
ip -s link
cat
readlink
basename
grep
awk
sed
sort
```

Nicht verwendet werden insbesondere:

```bash
ethtool -s
ip link set
ifconfig ... up
ifconfig ... down
systemctl restart networking
ifreload
ifup
ifdown
```

Es werden keine Interfaces veraendert, keine Links herunter- oder hochgesetzt und keine Counter zurueckgesetzt.

## Ablage

```text
outputfiles/<Run-ID>/     Einzel-Collector-CSVs
evidencefiles/<Run-ID>/   Raw-Evidence/Command-Ausgaben
runlogs/<Run-ID>/         Execution Summary und Collector-Logs
mergedfiles/<Run-ID>/     Konsolidierte CSVs fuer den XLSX-Import
```

## Erwartete Validierung

Nach einem Testlauf auf einem PVE-Testnode sind mindestens zu pruefen:

1. Reale physische Interfaces werden erkannt.
2. `lo`, Bridges, Bonds und virtuelle PVE-/Linux-Interfaces werden nicht als physische ethtool-Ziele verwendet.
3. Fuer jedes erkannte physische Interface existieren eigene `Physical NIC Stats`-Datensaetze.
4. `Befehl/Quelle` enthaelt echte Befehle wie `ethtool -S eno1`.
5. Ein direkter `ethtool -S <Interface>`-Counterwert stimmt mit dem Collector-Wert ueberein.
6. Ein gelesener Counterwert `0` bleibt `0`.
7. Fehlgeschlagene Abfragen erzeugen Statuswerte statt numerischer Nullwerte.
8. Merge und XLSX-Import funktionieren weiterhin ohne neue Spalten.

## Versionshinweis

Der Paketstand ist `V0.5.1` mit Datum `2026-08-25`.

Interne Header oder Kommentare einzelner geerbter Scripts koennen weiterhin aeltere Versionsstaende nennen. Fuer diesen Paketstand ist die technische Korrektur in `11-ceph-perf.sh` massgeblich; der fachliche V0.5-Scope bleibt ansonsten unveraendert.
