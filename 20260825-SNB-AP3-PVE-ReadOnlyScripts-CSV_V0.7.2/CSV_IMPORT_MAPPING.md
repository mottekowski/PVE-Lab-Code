# CSV-Import-Mapping – AP3 V0.7.2

## 1. CSV-Datenschema

Reguläre AP3-Data-Capture-Dateien verwenden unverändert sieben Spalten:

```text
Komponente/Scope;Kategorie;Parameter;Wert;Befehl/Quelle;Zeitstempel;Validiert (Y/N)
```

Reihenfolge und Semantik entsprechen V0.7.1.

## 2. Getrennte Merged Files

### PVE

`PVE-Merged/<Run-ID>/`

- `<Run-ID>_PBS_Anbindung_AllTargets.csv`
- `<Run-ID>_PBS_Storage_AllTargets.csv` – Header-only/NOT_APPLICABLE auf PVE-Seite
- `<Run-ID>_Policies_Retention_AllTargets.csv`
- `<Run-ID>_RTO_RPO_AllTargets.csv` – Header-only/NOT_APPLICABLE auf PVE-Seite
- `<Run-ID>_Evidence_Index.csv`

### PBS

`PBS-Merged/<Run-ID>/`

- `<Run-ID>_PBS_Anbindung_AllTargets.csv`
- `<Run-ID>_PBS_Storage_AllTargets.csv`
- `<Run-ID>_Policies_Retention_AllTargets.csv`
- `<Run-ID>_RTO_RPO_AllTargets.csv`
- `<Run-ID>_Evidence_Index.csv`

Es gibt keinen automatischen PVE+PBS-Cross-Merge.

## 3. Herkunftsnachweis

Die Herkunft bleibt ohne zusätzliche CSV-Spalte über Verzeichnis, Run-ID, `Komponente/Scope`, `Befehl/Quelle` und den jeweiligen Evidence Index nachvollziehbar.

## 4. Analyse des bereitgestellten Templates

**Datei:**

```text
20268325_Template_AP1_DataCapture_StromnetzBerlin_OT_ProxMox_Ceph_DC1-DC2.xlsx
```

Technisch festgestellt:

- Workbook-Zweck: AP1 Data Capture.
- Sheets: `Overview`, `ProxMox_Cluster`, `Ceph_Cluster`, `Network_Platform`, `DC2_Readiness`, `Risks_Issues`, `Data_Gaps`.
- Keine AP3-Sheets `PBS_Anbindung`, `PBS_Storage`, `Policies_Retention`, `RTO_RPO`, `Evidence_Index`.
- AP1-Collector-Referenzschema im Projekt nutzt für technische AP1-Merges acht Spalten inkl. `Kommentar`; dies unterscheidet sich vom AP3-Schema.

### Ergebnis

```text
PVE-Merged -> AP3-Schema: PASS
PBS-Merged -> AP3-Schema: PASS
Direktimport des vollständigen AP3-Ergebnisses in das genannte AP1-Workbook: FAIL / TEMPLATE_INTERFACE_GAP
Template geändert: NEIN
```

Eine automatische Anpassung wurde bewusst nicht implementiert, weil dadurch entweder die AP3-Semantik oder die Struktur des ausdrücklich unverändert zu lassenden Workbooks verändert würde.

## 5. Weiteres Vorgehen für den Workbook-Import

Für den vollständigen AP3-Import ist ein Workbook mit den AP3-Zielreitern bzw. eine ausdrücklich freigegebene Mapping-Entscheidung erforderlich. Bis dahin bleiben die Merged CSV Files technisch stabil und getrennt auswertbar.
