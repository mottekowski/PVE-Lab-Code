# TEMPLATE_INTERFACE_GAP – AP3 V0.7.2

## 1. Geprüfte Datei

```text
20268325_Template_AP1_DataCapture_StromnetzBerlin_OT_ProxMox_Ceph_DC1-DC2.xlsx
```

Die Datei wurde als technische Importreferenz analysiert und nicht verändert.

## 2. Festgestellte Struktur

Vorhandene Worksheets:

```text
Overview
ProxMox_Cluster
Ceph_Cluster
Network_Platform
DC2_Readiness
Risks_Issues
Data_Gaps
```

Das Workbook bezeichnet sich selbst als **AP1 Data-Capture Template**.

Nicht vorhanden sind die für das bestehende AP3-Modell verwendeten Reiter:

```text
PBS_Anbindung
PBS_Storage
Policies_Retention
RTO_RPO
Evidence_Index
```

## 3. Schnittstellenabweichung

Die bestehende AP3-Schnittstelle V0.7.1/V0.7.2 verwendet sieben technische Spalten:

```text
Komponente/Scope
Kategorie
Parameter
Wert
Befehl/Quelle
Zeitstempel
Validiert (Y/N)
```

Die im Projekt vorhandene AP1-Collector-/Merge-Struktur verwendet für die technischen AP1-Merges dagegen acht Spalten, u. a. mit zusätzlichem `Kommentar`, und andere fachliche Sheet-Zuordnungen.

## 4. Bewertung

Ein vollständiges AP3-Ergebnis kann nicht semantisch korrekt in das genannte AP1-Workbook importiert werden, ohne mindestens eine der folgenden Änderungen vorzunehmen:

1. Workbook-Struktur erweitern/ändern,
2. AP3-Schema und Fachmapping ändern,
3. eine explizite fachliche Mapping-Entscheidung treffen, die PBS-Daten in AP1-Reiter umdeutet.

Alle drei Varianten liegen außerhalb der Anforderung "Template bleibt in seiner Form bestehen".

## 5. Entscheidung in V0.7.2

V0.7.2:

- verändert das XLSX nicht,
- verändert die 7-spaltige AP3-Schnittstelle nicht,
- remappt PBS-Daten nicht künstlich auf AP1-Reiter,
- dokumentiert die Abweichung als `TEMPLATE_INTERFACE_GAP`.

Für einen vollständigen AP3-XLSX-Import ist ein AP3-Template oder eine explizit freigegebene Mapping-Entscheidung erforderlich.
