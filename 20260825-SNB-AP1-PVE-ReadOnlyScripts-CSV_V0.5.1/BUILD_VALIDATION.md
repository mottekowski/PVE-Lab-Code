# Build Validation - V0.5

Build-Datum: 2026-08-20

## Ergebnis

- Bash-Syntax aller Top-Level- und Library-Shell-Skripte: **OK**
- Perl-Syntax `lib/ap1-json.pl`: **OK**
- Geerbte V0.4.2-Scripts/Helfer byte-identisch: **OK**
- Static Read-only Audit der neuen V0.5-Skripte: **OK**
- Acht-Spalten-CSV-Schema der neuen Collector im Mock-Test: **OK**
- Permissions-Datenminimierung im Mock-Test: **OK**; freie Kommentare/E-Mail-/Namensfelder wurden nicht in die neue Evidence uebernommen
- HA leer/Legacy Statusbehandlung: **OK**
- V0.5-Wrapper Multi-Node Extension/Coverage/Merge-Sequenz: **OK**
- Bestehender Merge nimmt neue `ProxMoxCluster`-CSV-Dateien ohne Codeaenderung auf: **OK**
- Kompatibilitaet zum bestehenden `ProxMox_Cluster` Acht-Spalten-Header des AP1-XLSX: **OK**

## Read-only-Grenzen

Die neuen Collector verwenden nur GET/List/Show/Read-Operationen. Es werden insbesondere keine ACLs, Rollen, Benutzer, Tokens, HA-Ressourcen, Watchdogs oder Quorum-Werte veraendert und kein Fencing/Failover-Test ausgeloest.

## Hinweis

Die Mock-/Testvalidierung prueft Scriptlogik, Format und Robustheit. Die fachliche Interpretation realer Daten erfolgt erst nach der Erfassung auf der vorgesehenen Zielumgebung.
