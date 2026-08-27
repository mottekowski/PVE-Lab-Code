# Changelog

## V0.7.2 – 2026-08-25

### Architektur

- PVE- und PBS-Erfassung vollständig getrennt.
- Identisches Paket wird separat in PVE und PBS bereitgestellt.
- PVE-Ausführung aus `PVE-Scripts`, PBS-Ausführung aus `PBS-Scripts`.
- Kein PVE->PBS-SSH und kein PBS->PVE-SSH erforderlich.
- PVE-Collector erfasst weiterhin alle PVE-Nodes des Zielclusters.
- PBS-Collector läuft ausschließlich lokal auf PBS.

### Output und Merge

- Getrennte Raw-Verzeichnisse: `PVE-Out` und `PBS-Out`.
- Getrennte lokale Merge-Verzeichnisse: `PVE-Merged` und `PBS-Merged`.
- Je Umgebung eigener Merge; kein automatischer Cross-System-Merge.
- AP3-Fachdateien und 7-spaltige CSV-Schnittstelle bleiben erhalten.
- V0.7.1-Normalisierung bekannter Unicode-CLI-Tabellen bleibt erhalten.

### PBS Scope-Isolation

- PVE-Erhebung erzeugt einen nicht sensitiven `AP3_PBS_Scope.csv`-Handoff.
- Scope-Datei wird manuell in die PBS-Umgebung übertragen.
- PBS-Datastore-/Namespace-Erhebung wird auf den PVE-definierten Scope begrenzt.
- Keine Task-Korrelation nur anhand identischer VMIDs.
- Bei nicht eindeutiger Namespace-Zuordnung wird keine globale Task-Historie exportiert.

### PBS Berechtigungen

- Vollständige lokale CLI-/Host-Erhebung standardisiert auf EUID 0.
- Direkter Root-Login ist nicht notwendig; `sudo -n` kann die lokale Ausführung privilegieren.
- Kein interaktives sudo und keine Passwortspeicherung.
- Berechtigungsmodell in `PBS_BERECHTIGUNGEN.md` dokumentiert.

### Template-Prüfung

- `20268325_Template_AP1_DataCapture_StromnetzBerlin_OT_ProxMox_Ceph_DC1-DC2.xlsx` analysiert und nicht verändert.
- Workbook ist ein AP1-Template ohne AP3-Fachreiter.
- `TEMPLATE_INTERFACE_GAP` dokumentiert; keine künstliche Remap-Logik in V0.7.2.

### Nicht geändert

- Read-only-Grundsatz.
- Datenschutz-/Secret-Ausschluss.
- AP3-Statussemantik.
- Keine aktive Restore-/Verify-/Prune-/GC-/Sync-/iPerf-Ausführung.
