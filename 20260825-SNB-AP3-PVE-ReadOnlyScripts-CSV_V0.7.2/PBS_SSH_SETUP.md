# PBS SSH Setup – ab V0.7.2 nicht mehr verwendet

## Status

**OBSOLET FÜR DEN AKTUELLEN COLLECTOR-WORKFLOW**

Bis einschließlich V0.7.1 wurde PBS aus dem PVE-Collector heraus per SSH erfasst. Dieses Betriebsmodell wird mit V0.7.2 ausdrücklich beendet.

## V0.7.2

- PVE -> PBS SSH/TCP22: nicht erforderlich und darf geblockt sein.
- PBS -> PVE SSH/TCP22: nicht erforderlich und darf geblockt sein.
- Das Scriptpaket wird separat in beide Umgebungen kopiert.
- PVE-Ausführung erfolgt lokal aus `PVE-Scripts`.
- PBS-Ausführung erfolgt lokal aus `PBS-Scripts`.
- Der einzige Handoff ist `AP3_PBS_Scope.csv`; er wird manuell über einen freigegebenen administrativen Weg übertragen.

Für das lokale PBS-Berechtigungsmodell siehe `PBS_BERECHTIGUNGEN.md`.
