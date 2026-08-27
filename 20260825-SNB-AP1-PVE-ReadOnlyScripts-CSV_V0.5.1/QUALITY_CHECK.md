# Quality Check - AP1 Collector V0.5

## Ziel

V0.5 soll Permissions als technische CORE-Baseline ergaenzen und HA als ARCHITECTURE_CRITICAL/CORE vertiefen, ohne die bestehende Collection-/Merge-/CSV-Architektur zu veraendern.

## Build-/Regression-Pruefungen

- `bash -n` fuer alle Bash-Skripte
- `perl -c lib/ap1-json.pl`
- alle neuen CSVs exakt acht Spalten
- V0.5-Dateinamen folgen der bestehenden `YYYYMMDD_HHMM_Nummer_Host_Kategorie_Was.csv`-Nomenklatur
- neue Collector 13/14/15 nutzen `ProxMoxCluster` und werden vom bestehenden Merge erfasst
- geerbte `.sh`-/`.pl`-Dateien aus V0.4.2 sind byte-identisch
- keine schreibenden PVE-/HA-/Watchdog-Kommandos in den neuen Collectorn
- `/dev/watchdog` wird nicht geoeffnet
- keine Token-Secrets/Passwoerter/Private Keys/Recovery Keys in CSV oder Evidence
- keine freien User-/Group-/Token-Kommentare oder E-Mail-/Namensfelder in den neuen Permissions-Evidenzen
- leere Rollen/Gruppen/ACLs/Tokens bzw. nicht konfigurierte HA-Features erzeugen eindeutige Statuszeilen
- PVE-9-HA-Rules und Legacy-HA-Groups werden versionsrobust behandelt
- bestehende V0.4.2-Quality-Fixes bleiben aufgrund byte-identischer Basis erhalten

## Durchgefuehrte V0.5-Mock-Tests

- Permissions mit Built-in-/Custom-Roles, Groups, ACLs und Token-Metadaten: erfolgreich.
- Mock-Datensaetze mit E-Mail, Vorname und freien Kommentaren: nicht in CSV/Evidence des neuen Permissions-Collectors enthalten.
- HA Resource/Rule/Workload-Korrelation: erfolgreich.
- Leere/Legacy-HA-Situation: `NO_HA_RESOURCES_CONFIGURED`, `FEATURE_NOT_AVAILABLE_IN_PVE_VERSION`, `NO_HA_GROUPS_CONFIGURED` und `NO_DATA` werden differenziert ausgegeben.
- Node-HA-Service-/Watchdog-Erfassung: read-only mit achtspaltigem CSV-Schema.
- Additiver Wrapper: 13/14 clusterweit einmal und 15 auf allen Online-Nodes; anschliessend bestehender Merge.

## Erwartete operative Validierung in der Testumgebung

1. V0.5 ueber `00-ap1-v05-collect.sh` starten.
2. Bestehende V0.4.2-Ergebnisse muessen wie bisher entstehen.
3. `13_*_ProxMoxCluster_PVEPermissions.csv` genau einmal pro Run.
4. `14_*_ProxMoxCluster_PVEHACore.csv` genau einmal pro Run.
5. `15_*_ProxMoxCluster_PVEHANode.csv` je ONLINE Node genau einmal.
6. Bei drei Online-Nodes insgesamt 32 Einzel-CSVs erwarten.
7. `mergedfiles/<Run-ID>/<Run-ID>_ProxMoxCluster_AllHosts.csv` enthaelt auch 13/14/15.
8. Import in `ProxMox_Cluster` erfolgt ohne neue Spalten oder neuen Reiter.
9. Inhalte fachlich pruefen; `Validiert (Y/N)` bleibt bis zur manuellen Validierung `N`.
