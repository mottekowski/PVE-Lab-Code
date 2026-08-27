# Arbeitsanweisungen – PVE-Lab-Code

## 1. Zweck und Scope

Dieses Verzeichnis ist der primäre Arbeitsbereich für den technischen Code des PVE-Labs und der zugehörigen Analysewerkzeuge.

ChatGPT/Codex soll hier insbesondere arbeiten mit:

- Terraform;
- PowerShell;
- Bash/Shell;
- Azure CLI;
- Proxmox VE CLI/API;
- Ceph CLI;
- Git;
- optional später Ansible.

Ziel ist kein maximal abstrahiertes Enterprise-Framework, sondern **lesbarer, reproduzierbarer und sicher prüfbarer Code für ein Test- und Analyse-Lab**.

---

## 2. Verzeichnisstruktur und Bedeutung

### `.vscode/`

VS-Code-Projektkonfiguration.

Nur ändern, wenn die Aufgabe ausdrücklich Editor-, Task-, Launch- oder Workspace-Konfiguration betrifft.

### `.graphify/`, `.sonarlint/` und andere Tool-Caches

Als Tool-/Analyseartefakte behandeln.

Nicht ohne ausdrücklichen Auftrag als Source-Code bearbeiten oder großflächig versionieren.

### `scripts/`

Operative PowerShell-/Shell-Skripte für Lab-Betrieb und Azure-/PVE-Abläufe.

`Archiv/` enthält historische Stände und ist standardmäßig read-only.

### `terraform/access-services/`

Terraform für schaltbare Azure Access Services des Labs, insbesondere NAT Gateway und Azure Bastion.

Die vorhandene Terraform-Architektur respektieren; keine unnötige Modulkomplexität einführen.

### `20260820-SNB-AP1-PVE-ReadOnlyScripts-CSV_V0.5/`

Versionierter AP1-Collector-/Analyse-Stand.

### `20260821-SNB-AP3-PVE-ReadOnlyScripts-CSV_V0.6/`

Versionierter AP3-Collector-/Analyse-Stand.

Versionierte AP-Verzeichnisse sind grundsätzlich als reproduzierbare Baselines zu behandeln. Bestehende Stände nur ändern, wenn die konkrete Aufgabe genau diese Version adressiert. Bei funktionalen Weiterentwicklungen bevorzugt einen neuen Versionsstand erzeugen, sofern die Aufgabe nichts anderes vorgibt.

---

## 3. Verbindliche Lab-Architektur

Code darf die festgelegte Architektur nicht stillschweigend verändern:

- `pve01`, `pve02`, `pve03`;
- ein gemeinsames Azure LAB-Subnetz;
- eine Azure NIC pro PVE-Node;
- Management, SSH, GUI, API, Corosync und Ceph über dasselbe Netz;
- internes Ceph auf drei Nodes;
- mindestens ein Ceph-OSD pro Node auf separaten Managed Data Disks;
- keine OSDs auf der Systemdisk;
- Nested-Testnetz über `vmbr-lab` mit Routing/NAT;
- keine transparente Layer-2-Erweiterung des Azure-Netzes zu Nested VMs;
- keine Multi-NIC- oder Policy-Based-Routing-Konstruktion ohne neue explizite Architekturentscheidung.

Azure ist kein klassisches Layer-2-Datacenter. Code für Nested Networking muss Azure-konformes Routing oder NAT verwenden.

---

## 4. Allgemeine Coding-Regeln

Vor Änderungen:

1. relevante Dateien vollständig lesen;
2. bestehende Schnittstellen und Abhängigkeiten bestimmen;
3. generierte Dateien von Source-Dateien unterscheiden;
4. vorhandene Namens-, Logging- und Fehlerbehandlungskonventionen übernehmen;
5. erst dann den kleinsten sinnvollen Patch erstellen.

Regeln:

- keine unnötigen Komplett-Rewrites;
- keine kosmetischen Massenänderungen außerhalb des Tasks;
- bestehende Dateinamen und Aufrufparameter möglichst stabil halten;
- Fehlerfälle explizit behandeln;
- idempotente bzw. wiederholbare Abläufe bevorzugen;
- zerstörerische Aktionen nicht als versteckte Seiteneffekte einführen;
- keine Secrets in Code, Logs oder Beispielen;
- unbekannte Company-Werte als Variablen/Platzhalter abbilden;
- vorhandene Kommentare nur ändern, wenn sie technisch falsch oder durch die Änderung überholt sind.

---

## 5. Terraform-Regeln

Terraform verwaltet Azure-Infrastruktur. Für Änderungen gilt grundsätzlich dieser Ablauf:

1. Code ändern;
2. `terraform fmt`;
3. `terraform validate`;
4. `terraform plan`;
5. Plan auf Add/Change/Destroy prüfen;
6. `terraform apply` nur auf ausdrücklichen Auftrag.

### Verbindliche Regeln

- **Kein automatisches `terraform destroy`.**
- Kein Apply allein deshalb ausführen, weil ein Plan erfolgreich war.
- Remote State nicht manuell editieren.
- State-Dateien und vertrauliche `tfvars` nicht in Git aufnehmen.
- `.terraform/` ist kein Source-Code.
- Provider- oder Terraform-Versionen nicht ohne fachlichen Grund aktualisieren.
- Bestehende `for_each`, Variablen, `locals` und Outputs bevorzugen, wenn dadurch Lesbarkeit erhalten bleibt.
- Für drei Nodes Lesbarkeit vor maximaler Abstraktion priorisieren.
- Keine Ressourcen-IDs, Subscription-IDs, Regionen oder Company-Namen erfinden.

### Typische Prüfungen

Im Terraform-Verzeichnis:

```powershell
terraform fmt -check -recursive
terraform validate
terraform plan
```

Wenn Backend-/Provider-Zugriff fehlt, nicht so tun, als wäre der Plan ausgeführt worden. Stattdessen klar angeben, welche Prüfung lokal möglich war und welche nicht.

---

## 6. Access-Services: NAT und Bastion

Das Lab verwendet schaltbare Azure Access Services, um Kosten zu reduzieren.

Bei Änderungen an `terraform/access-services` oder den zugehörigen PowerShell-Skripten beachten:

- ON- und COLD-Zustand müssen zueinander konsistent bleiben;
- persistente Public IPs nicht versehentlich löschen, wenn das bestehende Design sie beibehält;
- NAT-Gateway-, Public-IP- und Subnet-Associations getrennt prüfen;
- Bastion-Tunneling und die vorhandene SKU-/Konfiguration nicht stillschweigend ändern;
- wiederholte ON-/COLD-Läufe müssen einen bereits korrekten Zustand erkennen können;
- vor destruktiven Änderungen den Terraform-Plan explizit auf `destroy` prüfen.

Keine neue Access-Service-Architektur einführen, wenn nur ein bestehendes Script korrigiert werden soll.

---

## 7. PowerShell-Regeln

Für PowerShell-Skripte:

- vorhandenen Parameterstil und Namenskonventionen beibehalten;
- klare Fehlerausgaben und nicht-null Exit-Verhalten bei echten Fehlern bevorzugen;
- Azure CLI-/Terraform-Aufrufe auf Exit Codes prüfen;
- Ressourcenstatus vor Änderungen ermitteln, wenn dies die Wiederholbarkeit verbessert;
- keine Credentials hart codieren;
- keine destruktive Standardaktion ohne expliziten Task;
- bei Betriebs-Skripten sinnvolle Read-/Check-Phasen von Change-Phasen trennen.

Wenn ein Script Azure-Ressourcen entfernt, dealloziert, stoppt oder neu erzeugt, muss aus Code und Ausgabe eindeutig hervorgehen, **was** geändert wird.

---

## 8. Bash-/Read-only-Collector-Regeln

AP1-/AP3-Collector und Assessment-Skripte müssen read-only bleiben, sofern die Aufgabe nicht ausdrücklich einen anderen Typ von Script verlangt.

### Read-only bedeutet insbesondere

Nicht verwenden, um den Zielzustand zu ändern:

- `pvesh create`, `pvesh set`, `pvesh delete`;
- `qm set`, `qm create`, `qm destroy`;
- `pct set`, `pct create`, `pct destroy`;
- `pvecm add`, Cluster-Create/Join-Kommandos;
- `pveceph create*`, `pveceph destroy*`;
- `ceph osd out/in`, `ceph config set`, Pool-/OSD-/MON-/MGR-Änderungen;
- schreibende Systemkonfiguration;
- Paketinstallation oder Service-Neustarts;
- Lösch-, Move- oder Bereinigungskommandos auf Kundendaten.

Read-only Abfragen wie `pvesh get`, `pvecm status`, `ceph status`, `ceph osd tree`, `qm config`, `pct config`, Datei-Lesezugriffe und vergleichbare Diagnosekommandos sind zulässig.

### Output-Anforderungen

Collector-Ausgaben sollen:

- stabile und eindeutige Statuswerte verwenden;
- fehlende Features robust behandeln;
- leere ACL-/Role-/Group-/HA-Ergebnisse ohne Fehler verarbeiten;
- keine Secrets exportieren;
- keine technisch unnötigen personenbezogenen Daten exportieren;
- CSV-/Template-Rückwärtskompatibilität berücksichtigen;
- Host-/Cluster-Unterschiede erkennbar machen;
- Fehler und `not present`/`not configured` klar unterscheiden.

Bei Änderungen immer prüfen, ob bestehende Import-Templates weiterhin funktionieren.

---

## 9. Proxmox- und Ceph-Regeln

Bei Proxmox-/Ceph-Code:

- Clusterzustand zuerst lesen, erst dann gegebenenfalls ändern;
- bestehende Cluster-Mitgliedschaft erkennen;
- Quorum nicht gefährden;
- Corosync-/pmxcfs-Konfiguration nicht leichtfertig editieren;
- Ceph MON/MGR/OSD-Zustand vor und nach Änderungen validieren;
- OSD-Geräte eindeutig identifizieren;
- keine Systemdisk als Ceph-OSD verwenden;
- Hostnamen und Namensauflösung stabil halten;
- Zeitsynchronisation berücksichtigen.

Für dieses Lab genügt ein technisch sauberer Testbetrieb; keine produktive Ceph-HA- oder Performance-Komplexität hinzufügen.

---

## 10. Ansible-Regeln für spätere Ergänzungen

Falls Ansible-Dateien ergänzt werden:

- Module vor `shell`/`command` bevorzugen;
- `shell`/`command` nur einsetzen, wenn PVE/Ceph-Funktionen keine robuste Modullösung bieten;
- Cluster-Erstellung und Node-Join idempotent gestalten;
- bestehende Mitgliedschaften erkennen;
- Ceph-Installation und OSD-Erstellung gegen Wiederholung absichern;
- keine Secrets im Klartext;
- Inventories und Variablen sauber von Credentials trennen.

---

## 11. Validierung vor Abschluss

Je nach geänderter Technologie passende Prüfungen ausführen.

### Allgemein

```bash
git diff --check
git status --short
git diff
```

### Bash

Wenn verfügbar:

```bash
bash -n <script.sh>
shellcheck <script.sh>
```

### PowerShell

Wenn PowerShell/PSScriptAnalyzer verfügbar ist:

```powershell
Invoke-ScriptAnalyzer -Path <script.ps1>
```

Zusätzlich Syntax, Parameter und aufgerufene Pfade prüfen.

### Terraform

```powershell
terraform fmt -check -recursive
terraform validate
terraform plan
```

Keine Prüfung als erfolgreich melden, wenn sie nicht tatsächlich ausgeführt wurde.

---

## 12. Git- und Versionsregeln

Nicht committen:

- `.terraform/`;
- Terraform State;
- geheime `tfvars`;
- private Schlüssel;
- Tokens und Passwörter;
- temporäre Collector-Outputs, sofern diese nicht bewusst als Testevidenz versioniert werden sollen;
- Cache-Inhalte ohne fachlichen Nutzen.

Bei versionierten Collector-Verzeichnissen bestehende Releases nicht stillschweigend überschreiben.

Wenn eine neue Version erforderlich ist:

- Versionsnummer konsistent erhöhen;
- interne Banner/Versionsangaben anpassen;
- Pfade und README/Usage-Hinweise konsistent halten;
- Änderungen gegenüber der Vorversion nachvollziehbar dokumentieren.

---

## 13. Erwarteter Abschlussbericht

Nach Codeänderungen liefern:

- Liste der geänderten/neuen Dateien;
- kurze technische Begründung;
- ausgeführte Prüfungen und Resultate;
- nicht ausgeführte Prüfungen mit Grund;
- mögliche Auswirkungen auf Terraform State, Azure-Ressourcen, PVE/Ceph oder AP-Template-Importe;
- offene Punkte nur dann, wenn tatsächlich noch ein technisches Risiko besteht.

Keine Azure-, PVE-, Ceph- oder Git-Änderung behaupten, die nicht tatsächlich ausgeführt bzw. aus vorhandener Evidenz verifiziert wurde.
