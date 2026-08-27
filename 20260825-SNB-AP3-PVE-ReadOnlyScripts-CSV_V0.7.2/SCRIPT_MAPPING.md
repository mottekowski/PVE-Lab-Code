# Script-Zuordnung V0.7.1 -> V0.7.2

Die V0.7.1-Baseline wurde fachlich in PVE- und PBS-Bereiche getrennt. Die Erfassungsinhalte wurden soweit möglich übernommen; Cross-Zone-SSH wurde entfernt.

| V0.7.1 | V0.7.2 | Rolle / Begründung |
|---|---|---|
| `AP3-31-PBSNet.sh` | `PVE-Scripts/AP3-31-PBSNet.sh` | PVE-seitige Erreichbarkeit/DNS/Route zum PBS; keine PBS-SSH-Verbindung |
| `AP3-31-PBSBack.sh` | entfällt als aktiver Collector | PBS->PVE-Gegenprobe widerspricht der getrennten Architektur; Status wird in `AP3-20-PBSSystem.sh` als `NOT_EXECUTED` dokumentiert |
| `AP3-32-PBSTLS.sh` | `PVE-Scripts/AP3-32-PBSTLS.sh` | TLS-Sicht vom PVE auf PBS TCP/8007 |
| `AP3-33-PBSRepo.sh` | `PVE-Scripts/AP3-33-PBSRepo.sh` | PVE-seitige PBS Storage-Konfiguration und Scope-Selektoren |
| `AP3-51-PVEJobs.sh` | `PVE-Scripts/AP3-51-PVEJobs.sh` | PVE Backup-Jobs und `prune-backups` |
| `AP3-20-PBSSystem.sh` | `PBS-Scripts/AP3-20-PBSSystem.sh` | lokaler PBS System-/Dienststatus |
| `AP3-32-PBSCert.sh` | `PBS-Scripts/AP3-32-PBSCert.sh` | lokaler PBS Zertifikatsstatus |
| `AP3-33-PBSAuth.sh` | `PBS-Scripts/AP3-33-PBSAuth.sh` | PBS Auth-/ACL-Sicht, datensparsam und scope-gefiltert |
| `AP3-41-PBSStore.sh` | `PBS-Scripts/AP3-41-PBSStore.sh` | scoped Datastore-Konfiguration/Kapazität |
| `AP3-42-PBSHealth.sh` | `PBS-Scripts/AP3-42-PBSHealth.sh` | scoped Storage-/Filesystem-Health |
| `AP3-43-PBSPerf.sh` | `PBS-Scripts/AP3-43-PBSPerf.sh` | passive scoped Performance-Indikatoren + markierter Host-Kontext |
| `AP3-52-PBSPrune.sh` | `PBS-Scripts/AP3-52-PBSPrune.sh` | scoped Prune-Konfiguration; kein Prune-Run |
| `AP3-53-PBSVerify.sh` | `PBS-Scripts/AP3-53-PBSVerify.sh` | scoped Verify-Konfiguration/Historie; kein Verify-Run |
| `AP3-54-PBSGC.sh` | `PBS-Scripts/AP3-54-PBSGC.sh` | scoped GC-Status; kein GC-Start |
| `AP3-55-PBSSync.sh` | `PBS-Scripts/AP3-55-PBSSync.sh` | scoped Sync-Konfiguration; kein Sync-Run |
| `AP3-60-RTOEvidence.sh` | `PBS-Scripts/AP3-60-RTOEvidence.sh` | scope-gefilterte historische Task-Evidence; keine Restore-/Throughput-Tests |
| `Run-AP3-Collector.sh` | `Run-AP3-PVE-Collector.sh` + `Run-AP3-PBS-Collector.sh` | Collector vollständig getrennt |
| `90-ap3-merge.sh` | `Merge-AP3-PVE.sh` + `Merge-AP3-PBS.sh` | lokaler Merge pro Umgebung |
| `Build-AP3-EvidenceIndex.sh` | PVE-/PBS-spezifischer Evidence Builder | getrennte Herkunft und Run-ID |
| `lib/ap3-common.sh` | `lib/ap3-pve.sh`, `lib/ap3-pbs.sh`, `lib/ap3-csv.sh` | keine gemeinsame Cross-Zone-SSH-Funktion mehr |
| `lib/ap3-table.sh` | `lib/ap3-table.sh` | V0.7.1-Tabellennormalisierung beibehalten |

Neu in V0.7.2:

- `PVE-Scripts/Build-AP3-PBS-Scope.sh`
- `PBS-Scripts/Input/AP3_PBS_Scope.csv.example`
- `PBS_BERECHTIGUNGEN.md`
- `TEMPLATE_INTERFACE_GAP.md`
