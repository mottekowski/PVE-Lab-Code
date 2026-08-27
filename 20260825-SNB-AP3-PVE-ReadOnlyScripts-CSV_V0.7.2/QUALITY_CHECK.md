# Qualitätsprüfung – AP3 V0.7.2

## 1. Prüfumfang

V0.7.2 wurde auf folgende Punkte geprüft:

- Schlüssigkeit der getrennten PVE-/PBS-Erfassungsarchitektur
- Plausibilität der Scope-Isolation auf einem zentralen PBS
- Vollständigkeit der vorgesehenen PVE-/PBS-Fachgruppen
- Genauigkeit der CSV-Schnittstelle
- Konsistenz der Statuswerte
- Read-only-Verhalten
- Secret-/Datenschutzgrenzen
- V0.7.1-Tabellennormalisierung
- lokale PVE- und PBS-Merge-Funktion
- Template-Importreferenz

## 2. Architektur

| Prüfung | Ergebnis |
|---|---|
| PVE/PBS Collector getrennt | PASS |
| PVE -> PBS SSH erforderlich | NEIN |
| PBS -> PVE SSH erforderlich | NEIN |
| PVE-Nodes weiterhin über PVE-Collector erfassbar | PASS – synthetisch/statisch |
| PBS Collector lokal ausführbar | PASS – synthetisch/statisch |
| PVE-Out/PBS-Out getrennt | PASS |
| PVE-Merged/PBS-Merged getrennt | PASS |
| automatischer Cross-System-Merge | NICHT IMPLEMENTIERT |

## 3. PBS Scope-Isolation

- Datastore-Scope wird aus `AP3_PBS_Scope.csv` geladen.
- Unbekannte/fremde Datastores werden nicht als scoped Daten exportiert.
- Namespace-Scope wird berücksichtigt.
- Task-History wird nicht anhand einer VMID allein zugeordnet.
- Namespace-ambige Task-Historie wird nicht global exportiert.

Ergebnis: **PASS – synthetische Scope-Tests erforderlich/ausgeführt gemäß Testprotokoll der Paketbildung.**

## 4. PBS Privilege Validation

```text
Execution model : EUID 0
Direct root SSH : NOT_REQUIRED
Alternative     : dedicated Linux user + sudo -n collector
Interactive sudo: NOT_USED
```

Die Wahl von EUID 0 dient einer reproduzierbaren vollständigen lokalen CLI-/Host-Erhebung. PBS-API-Rollen `Audit`/`DatastoreAudit` sind ein separates Berechtigungsmodell und nicht gleichbedeutend mit lokalen Linux-Rechten.

Ergebnis: **PASS – Architektur/Dokumentation; Live-System muss operativ bestätigt werden.**

## 5. CSV

Regulärer AP3-Header:

```text
"Komponente/Scope";"Kategorie";"Parameter";"Wert";"Befehl/Quelle";"Zeitstempel";"Validiert (Y/N)"
```

- sieben Spalten
- semikolonsepariert
- doppelte Quotes escaped
- keine unbeabsichtigten Multiline-Records
- `Validiert (Y/N)` initial `N`

## 6. Read-only

Nicht ausgeführt werden:

- Restore
- Verify Run
- Prune Run
- Garbage Collection Start
- Sync Run
- iPerf/aktive Throughput-Tests
- PVE-/PBS-Konfigurationsänderungen
- Mount/Unmount

`NOT_EXECUTED`-Zeilen dokumentieren bewusst ausgeschlossene aktive Funktionen.

## 7. Datenschutz

Nicht vorgesehen sind Exporte von:

- Passwörtern
- Token-Secrets
- privaten Schlüsseln
- Recovery Keys
- Auth-Tickets
- Session-Tokens

Auth-IDs werden in PBS-ACL-/Sync-Kontexten redigiert. PVE-Accountreferenzen werden auf Realm/Token-Präsenz minimiert.

## 8. Template Import Validation

Geprüfte Datei:

```text
20268325_Template_AP1_DataCapture_StromnetzBerlin_OT_ProxMox_Ceph_DC1-DC2.xlsx
```

```text
Template gefunden/analysiert       : PASS
Template verändert                 : NEIN
Workbook ist AP1                   : JA
AP3-Fachreiter vorhanden           : NEIN
PVE-Merged 7-Spalten AP3-kompatibel: PASS
PBS-Merged 7-Spalten AP3-kompatibel: PASS
Direkter Vollimport in AP1-Workbook: FAIL / TEMPLATE_INTERFACE_GAP
```

Siehe `TEMPLATE_INTERFACE_GAP.md`.

## 9. Live-Lab-Status

**NICHT DURCHGEFÜHRT in dieser Erstellungsumgebung.**

Statische und synthetische Validierung kann die reale PVE-/PBS-Ausführung nicht ersetzen. Vor Freigabe für die Kundenerhebung ist jeweils ein echter Collector-Lauf in PVE und PBS einschließlich lokalem Merge und Importprüfung erforderlich.

## 10. Ergebnis der Paketbildungs-Tests

Synthetische Testläufe in der Erstellungsumgebung:

```text
bash -n aller Shell-Scripts                      : PASS
PVE Collector lokal + zwei Remote-PVE-Targets   : PASS
SSH-Ziele im PVE-Remote-Test nur PVE02/PVE03    : PASS
PVE -> PBS SSH als SSH-Ziel                      : NICHT VERWENDET
PBS Collector ohne PVE-Verbindung                : PASS
PBS zentral: Fremd-Datastore cluster-b-ds       : NICHT IM AP3-OUTPUT
Namespace-ambige Task-History                    : NICHT EXPORTIERT
AP3 7-Spalten-CSV, synthetische Records          : 211 Zeilen geprüft / PASS
Unicode-Boxrahmen in normalisierten CSV-Werten   : KEINE / PASS
PBS non-root ohne sudo-n                         : Exit 77, kein Passwortprompt / PASS
```

Merge-Regression im getrennten Modell:

```text
PVE-Merge:
  PBS_Anbindung       3/3  OK
  PBS_Storage         0/0  NOT_APPLICABLE
  Policies_Retention  1/1  OK
  RTO_RPO             0/0  NOT_APPLICABLE

PBS-Merge:
  PBS_Anbindung       3/3  OK
  PBS_Storage         3/3  OK
  Policies_Retention  4/4  OK
  RTO_RPO             1/1  OK
```

Die 0/0-Gruppen auf der PVE-Seite sind beabsichtigt: PBS-native Storage-/RTO-Evidence wird ausschließlich im lokalen PBS-Lauf erhoben.
