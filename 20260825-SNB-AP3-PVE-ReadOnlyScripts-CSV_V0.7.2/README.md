# AP3 Read-only Data Capture – V0.7.2

**Projekt:** Stromnetz Berlin OT – ProxMox / Ceph  
**Version:** V0.7.2  
**Stand:** 2026-08-25

## 1. Zweck

Dieses Paket erfasst AP3-Daten für **Backup/Restore & Resilienz**. Ab V0.7.2 sind PVE- und PBS-Erfassung vollständig getrennt. Dasselbe Paket wird in beide Umgebungen kopiert, aber jeweils nur aus dem vorgesehenen Script-Verzeichnis ausgeführt.

Es gibt **keine SSH-Abhängigkeit zwischen PVE und PBS**. Die PVE-Nodes eines Clusters werden weiterhin von einem PVE-Collector erfasst. Die PBS-Erfassung läuft lokal auf dem PBS-Host.

## 2. Verzeichnisstruktur

```text
20260825-SNB-AP3-PVE-ReadOnlyScripts-CSV_V0.7.2/
├── PVE-Scripts/
│   ├── Run-AP3-PVE-Collector.sh
│   ├── Merge-AP3-PVE.sh
│   ├── PVE-Out/
│   ├── PVE-Merged/
│   └── runlogs/
├── PBS-Scripts/
│   ├── Run-AP3-PBS-Collector.sh
│   ├── Merge-AP3-PBS.sh
│   ├── Input/
│   ├── PBS-Out/
│   ├── PBS-Merged/
│   └── runlogs/
├── lib/
├── README.md
├── CHANGELOG.md
├── CSV_IMPORT_MAPPING.md
├── QUALITY_CHECK.md
├── PBS_BERECHTIGUNGEN.md
├── PBS_SSH_SETUP.md
├── TEMPLATE_INTERFACE_GAP.md
├── SCRIPT_MAPPING.md
├── VERSION.txt
└── SHA256SUMS.txt
```

## 3. PVE-Erfassung

Das Paket auf den PVE-Collector kopieren und ausschließlich aus `PVE-Scripts` ausführen.

```bash
cd 20260825-SNB-AP3-PVE-ReadOnlyScripts-CSV_V0.7.2/PVE-Scripts
cp pve-hosts.txt.example pve-hosts.txt
# pve-hosts.txt anpassen
sudo ./Run-AP3-PVE-Collector.sh
```

Der lokale PVE-Host ist Collector. Weitere PVE-Nodes werden wie bisher per SSH gelesen. Der Collector versucht **keinen SSH-Zugriff auf PBS**.

Ergebnisse:

```text
PVE-Out/<Run-ID>/
PVE-Merged/<Run-ID>/
PVE-Merged/<Run-ID>/<Run-ID>_AP3_PBS_Scope.csv
```

Der Scope-Handoff enthält nur nicht geheime Selektoren: PVE-Cluster, PVE-PBS-Storage-ID, PBS-Server, Datastore und optional Namespace.

## 4. Manueller Scope-Handoff an PBS

Die Datei

```text
<Run-ID>_AP3_PBS_Scope.csv
```

wird über den freigegebenen administrativen Weg in die PBS-Umgebung übertragen und dort als

```text
PBS-Scripts/Input/AP3_PBS_Scope.csv
```

bereitgestellt. Das Paket überträgt diese Datei **nicht** selbst.

## 5. PBS-Erfassung

Dasselbe Paket wird auf den PBS-Host kopiert. Die PBS-Erfassung wird lokal aus `PBS-Scripts` ausgeführt.

Direkt als root:

```bash
cd 20260825-SNB-AP3-PVE-ReadOnlyScripts-CSV_V0.7.2/PBS-Scripts
./Run-AP3-PBS-Collector.sh
```

Oder mit einem dedizierten Linux-Benutzer, wenn nicht-interaktives sudo bereits freigegeben ist:

```bash
cd 20260825-SNB-AP3-PVE-ReadOnlyScripts-CSV_V0.7.2/PBS-Scripts
sudo -n ./Run-AP3-PBS-Collector.sh
```

Die aktuelle V0.7.2 standardisiert die vollständige lokale PBS-Erhebung auf **EUID 0**. Ein direkter SSH-Login als root ist dafür nicht notwendig. Bei `sudo -n` muss der privilegiert gestartete Scriptpfad root-owned und für den ausführenden Benutzer nicht schreibbar sein. Details: `PBS_BERECHTIGUNGEN.md`.

Ergebnisse:

```text
PBS-Out/<Run-ID>/
PBS-Merged/<Run-ID>/
```

## 6. Zentraler PBS – Scope-Isolation

Der PBS kann mehrere PVE-Cluster sichern. V0.7.2 verwendet deshalb `AP3_PBS_Scope.csv` als harte Filtergrenze:

- Datastore- und Namespace-bezogene Daten werden nur für den Scope erhoben.
- Prune-/Verify-/Sync-Informationen werden nur übernommen, wenn sie sicher dem Scope zuordenbar sind.
- Task-Historien werden nicht allein anhand einer VMID korreliert.
- Bei Namespace-Scope wird eine nicht eindeutig zuordenbare globale Task-Historie nicht exportiert.
- Authentifizierungsidentitäten werden minimiert/redigiert; Realm-Details werden nicht unnötig exportiert.

## 7. Getrennter Merge

Der Merge findet in jeder Umgebung separat statt.

PVE:

```bash
cd PVE-Scripts
./Merge-AP3-PVE.sh <Run-ID>
./Build-AP3-PVE-EvidenceIndex.sh <Run-ID>
```

PBS:

```bash
cd PBS-Scripts
./Merge-AP3-PBS.sh <Run-ID>
./Build-AP3-PBS-EvidenceIndex.sh <Run-ID>
```

Es gibt **keinen automatischen Cross-System-Merge** und keine automatische Netzwerkübertragung zwischen den Umgebungen.

## 8. Merged Files

Beide Umgebungen erzeugen weiterhin AP3-Fachdateien mit der bekannten 7-spaltigen Struktur:

```text
Komponente/Scope
Kategorie
Parameter
Wert
Befehl/Quelle
Zeitstempel
Validiert (Y/N)
```

Fachliche Zieldateien:

```text
*_PBS_Anbindung_AllTargets.csv
*_PBS_Storage_AllTargets.csv
*_Policies_Retention_AllTargets.csv
*_RTO_RPO_AllTargets.csv
*_Evidence_Index.csv
```

PVE-Merged enthält PVE-seitig erhebbare Fakten; PBS-Merged enthält lokal auf PBS erhobene, scope-gefilterte Fakten.

## 9. Verbindliche Template-Prüfung

Die bereitgestellte Datei

```text
20268325_Template_AP1_DataCapture_StromnetzBerlin_OT_ProxMox_Ceph_DC1-DC2.xlsx
```

wurde technisch analysiert und **nicht verändert**. Das Workbook ist nach Inhalt und Sheet-Struktur ein AP1-Template (`ProxMox_Cluster`, `Ceph_Cluster`, `Network_Platform`, `DC2_Readiness`, `Risks_Issues`, `Data_Gaps`) und enthält keine AP3-Reiter wie `PBS_Anbindung`, `PBS_Storage`, `Policies_Retention`, `RTO_RPO` oder `Evidence_Index`.

Daher besteht ein **TEMPLATE_INTERFACE_GAP**: Ein vollständiger AP3-Import in dieses AP1-Workbook ist ohne strukturelle/semantische Änderung des Templates oder der AP3-Schnittstelle nicht möglich. V0.7.2 verändert das Workbook nicht und remappt PBS-Daten nicht künstlich in AP1-Reiter. Details: `TEMPLATE_INTERFACE_GAP.md`.

Die 7-spaltige AP3-CSV-Schnittstelle bleibt deshalb gegenüber V0.7.1 erhalten.

## 10. Read-only und Datenschutz

Das Paket führt keine aktiven Restore-, Verify-, Prune-, Garbage-Collection-, Sync- oder iPerf-Operationen aus und ändert keine PVE-/PBS-Konfiguration.

Nicht exportiert werden insbesondere Passwörter, Token-Secrets, private Schlüssel, Recovery Keys, Auth-Tickets oder Session-Tokens. Benutzer-/Realm-Anteile werden soweit möglich minimiert oder redigiert.

## 11. Statuswerte

Die V0.7.1-Statussemantik bleibt bestehen, u. a.:

```text
NONE_CONFIGURED
NOT_CONFIGURED
NOT_APPLICABLE
NOT_SUPPORTED
COMMAND_NOT_SUPPORTED
PERMISSION_DENIED
COLLECTION_FAILED
NOT_EXECUTED
```

Fehlende Berechtigung wird nicht als "nicht konfiguriert" interpretiert.

## 12. Validierung

Im Paket wurden statische und synthetische Tests durchgeführt. Ein realer getrennter Collector-Lauf auf PVE und PBS ist weiterhin erforderlich, bevor V0.7.2 als im Kunden-/Lab-System technisch bestätigt gilt.
