# PBS Berechtigungsmodell – AP3 V0.7.2

## 1. Ergebnis der Prüfung

Für die **vollständige lokale CLI-/Host-Erhebung dieser V0.7.2-Implementierung** wird EUID 0 verwendet.

Das bedeutet nicht, dass ein direkter Login als `root` erforderlich ist. Unterstützt sind:

1. lokale Ausführung als `root`, oder
2. lokaler dedizierter Linux-Benutzer mit bereits freigegebenem nicht-interaktivem `sudo -n`, der den Collector mit EUID 0 startet.

Beispiel:

```bash
sudo -n ./Run-AP3-PBS-Collector.sh
```

Es gibt keinen Root-SSH-Zugriff von PVE nach PBS und keinen SSH-Zugriff von PBS nach PVE.

## 2. Warum erhöhte Linux-Rechte verwendet werden

V0.7.2 nutzt lokal `proxmox-backup-manager` und Host-/Storage-Abfragen. Laut Proxmox-Dokumentation exponiert `proxmox-backup-manager` die PBS-Management-API auf der Kommandozeile. Privilegierte Management-Operationen werden serverseitig durch den lokalen `proxmox-backup`-Dienst verarbeitet; dieser läuft als `root`.

Darüber hinaus liegen PBS-Konfigurationen unter `/etc/proxmox-backup/`, und einzelne Host-/Storage-Abfragen können je nach System-Hardening erhöhte Linux-Rechte erfordern.

Für dieses Scriptpaket wurde daher bewusst ein einheitlicher, reproduzierbarer lokaler EUID-0-Ausführungskontext gewählt, statt unterschiedliche Linux-Dateirechte und Backend-CLI-Verhaltensweisen pro Installation vorauszusetzen.

## 3. Linux-User und PBS Auth-ID sind nicht dasselbe

Zu unterscheiden sind:

- Linux-Benutzer: z. B. `root`, `pbsadmin`
- PBS Auth-ID: z. B. `root@pam`, `user@pbs`, `user@pam`, API-Token

PBS-Rollen wie `Audit` oder `DatastoreAudit` steuern API-Berechtigungen. Sie ersetzen nicht automatisch die Linux-Datei-/Prozessrechte eines lokalen Shell-Collectors.

## 4. Least-Privilege-Einordnung

PBS stellt read-only Rollen wie `Audit` und `DatastoreAudit` bereit. Ein vollständig API-basierter Collector mit minimalen PBS-API-Rechten wäre grundsätzlich ein separates Design. V0.7.2 baut die bestehende lokale CLI-/Host-Erfassung bewusst nicht zu einem neuen API-Collector um.

Der EUID-0-Kontext erweitert den fachlichen Scope des Scriptpakets nicht: Die Scripts bleiben read-only und führen keine Restore-, Verify-, Prune-, GC-, Sync- oder Konfigurationsänderungen aus.

## 5. Precheck-Verhalten

`Run-AP3-PBS-Collector.sh` prüft:

- aktueller Linux-User / UID,
- root ja/nein,
- `sudo -n` bei non-root,
- Verfügbarkeit von `proxmox-backup-manager`,
- Lesbarkeit und Inhalt von `Input/AP3_PBS_Scope.csv`.

Wenn der Collector nicht als root läuft und `sudo -n` nicht möglich ist, bricht er ohne Passwortprompt ab. Es wird kein interaktives sudo gestartet.


## 5.1 Sicherheitsanforderung bei sudo-n

Wenn ein dedizierter Linux-Benutzer den gesamten Collector über `sudo -n` startet, muss das Scriptpaket bzw. mindestens der privilegiert ausführbare Collector-Pfad **root-owned und für diesen Benutzer nicht schreibbar** sein. Andernfalls könnte eine veränderbare Scriptdatei zu einer unbeabsichtigten Privilegienausweitung führen.

Empfehlung:

- Paket nach der Bereitstellung mit Root-Eigentümer und restriktiven Schreibrechten versehen, oder
- einen root-owned Wrapper/Installationspfad verwenden, der exakt den freigegebenen Collector startet.

Eine sudoers-Freigabe sollte nicht pauschal `ALL` erlauben.

## 6. Befehlsklassen

| Befehlsklasse | Zweck | V0.7.2-Kontext |
|---|---|---|
| `proxmox-backup-manager ... list/status/info` | PBS-Konfiguration und Status | lokal, EUID 0 |
| `/etc/proxmox-backup/datastore.cfg` | scoped Datastore-Parameter | lokal, EUID 0 |
| `df`, `findmnt`, `lsblk` | scoped Filesystem/Backing Device | lokal, EUID 0 Collector-Kontext |
| `zpool`, `zfs`, `mdadm` | nur scoped Storage-Health, falls zutreffend | lokal, EUID 0 Collector-Kontext |
| `journalctl` | nur Warning/Error-Anzahl, kein Loginhalt | lokal, EUID 0 |
| `iostat` | kurze passive Stichprobe, falls vorhanden | lokal, EUID 0 Collector-Kontext |

`SMART` wird in V0.7.2 nicht automatisch exportiert, solange die Zuordnung Datastore -> physisches Gerät nicht eindeutig ist.

## 7. Offizielle Proxmox-Referenzen

Stand der Prüfung: Proxmox Backup Server Dokumentation 4.2.5-1.

- https://pbs.proxmox.com/docs/sysadmin.html
- https://pbs.proxmox.com/docs/services.html
- https://pbs.proxmox.com/docs/proxmox-backup-manager/man1.html
- https://pbs.proxmox.com/docs/configuration-files.html

Die Proxmox-Dokumentation beschreibt außerdem die Rollen `Audit` und `DatastoreAudit` für read-only API-Sichten.
