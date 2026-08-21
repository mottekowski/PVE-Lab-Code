# Normalisierungsprinzip - V0.5

V0.5 uebernimmt das bestehende Normalisierungsprinzip unveraendert und ergaenzt ausschliesslich neue Collector.

## Grundregel

**Eine CSV-Zeile entspricht einem atomaren technischen Parameter/Wert-Paar.**

Vollstaendige CLI-/JSON-Ausgaben werden nicht als mehrzeilige Excel-Zellen gespeichert. Raw-Ausgaben verbleiben als Evidence; bei den neuen Permissions-/HA-Collectorn werden sensible bzw. frei formulierte Felder bereits vor der Evidence-Ausgabe gefiltert, wenn dies zur Datenminimierung erforderlich ist.

## Bestehende Acht-Spalten-Schemata

`ProxMoxCluster` und `CephCluster`:

```text
Node/Scope;Kategorie;Parameter;Wert;Befehl/Quelle;Zeitstempel;Validiert (Y/N);Kommentar
```

`NetworkPlatform`:

```text
Node/Standort;Segment;Parameter;Wert;Befehl/Quelle;Zeitstempel;Validiert (Y/N);Kommentar
```

Die neuen V0.5-Collector 13, 14 und 15 nutzen ausschliesslich das bestehende `ProxMoxCluster`-Schema.

## Permissions

Permissions werden atomar nach Record-Typ strukturiert:

```text
Permissions / Roles
Permissions / Groups
Permissions / ACLs
Permissions / API Tokens
```

ACL-Daten sind so strukturiert, dass spaeter folgende Sicht ableitbar ist:

```text
Principal -> Realm -> Role -> Path -> Propagate
```

## HA

Die erweiterte HA-Sicht wird in folgende Kategorien getrennt:

```text
HA / Architecture Critical
HA / Status
HA / Manager-LRM
HA / Resources
HA / Placement Rules
HA / Workload Correlation
HA / Node Watchdog-Fencing
```

Nicht konfigurierte oder nicht verfuegbare Features werden als eindeutiger Status abgebildet und nicht als leere bzw. mehrdeutige Werte verschluckt.

## Konsolidierung

Der bestehende `90-ap1-merge.sh` arbeitet unveraendert. Da 13/14/15 im Dateinamen die Kategorie `ProxMoxCluster` tragen, werden diese automatisch in `ProxMoxCluster_AllHosts.csv` aufgenommen. Es entstehen keine neuen XLSX-Spalten.

## Zeitstempel und Zellgroesse

Die bestehende V0.4.2-Zeitzonenlogik bleibt unveraendert: Default `Europe/Berlin`, ISO 8601 mit Offset. Der bestehende Grenzwert fuer normalisierte `Wert`-Felder bleibt ebenfalls unveraendert.
