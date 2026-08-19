# Normalisierungsprinzip - V0.4.1

V0.4.1 übernimmt das fachliche Normalisierungsprinzip aus V0.2/V0.3 und ergänzt die Multi-Host-Erfassung.

## Grundregel

**Eine CSV-Zeile entspricht einem atomaren technischen Parameter/Wert-Paar.**

Terminaltabellen, JSON-Blöcke und mehrzeilige Konfigurationen werden nicht als komplette Zellinhalte gespeichert. Die vollständige unveränderte Befehlsausgabe bleibt als Evidence erhalten.

## Multi-Host-Regel

Der Collector-Prozess läuft auf einem Coordinator. `AP1_TARGET_HOST` bestimmt, auf welchem PVE-Node ein Read-only-Kommando ausgeführt wird. Bei einem Remote-Node wird ausschließlich das Kommando per SSH ausgeführt; Parsing, CSV-Erstellung, temporäre Verarbeitung und Evidence-Speicherung erfolgen auf dem Coordinator.

Damit ist der Hostname sowohl im Feld `Node/Scope` bzw. `Node/Standort` als auch im OUTPUT-Dateinamen nachvollziehbar.

## Dateinamen

```text
YYYYMMDD_HHMM_Nummer_Host_Kategorie_Was.csv
```

Das gemeinsame `YYYYMMDD_HHMM` bildet eine Collection-Run-ID und erlaubt, alle Dateien eines Kundentermins eindeutig zusammenzufassen.

## Konsolidierung

Die Merge-Logik entfernt ausschließlich wiederholte Headerzeilen. Fachliche Datensätze werden nicht dedupliziert oder verändert. Dies schützt die Nachvollziehbarkeit der jeweiligen Node-Sicht und Evidence-Referenz.

Drei sheet-kompatible Consolidated CSVs werden erzeugt:

- `ProxMoxCluster_AllHosts`
- `NetworkPlatform_AllHosts`
- `CephCluster_AllHosts`

Zusätzlich wird ein achtspaltiges `AP1_AllHosts_Review` für die gemeinsame Sicht aller Bereiche erzeugt.

## Zellgröße

Normalisierte `Wert`-Felder werden standardmäßig auf maximal 4.000 Zeichen begrenzt. Der ungekürzte Wert bleibt in der Evidence-Datei. Dies verhindert erneut den in V0.1 beobachteten Import-/Excel-Zellgrößenfehler.
