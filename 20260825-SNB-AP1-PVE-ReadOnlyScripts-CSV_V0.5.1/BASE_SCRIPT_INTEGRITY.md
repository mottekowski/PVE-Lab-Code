# Base Script Integrity - V0.5

V0.5 ist eine additive Erweiterung der vorhandenen V0.4.2-Basis.

Die folgenden bereits vorhandenen Scripts/Helfer duerfen gegenueber V0.4.2 nicht veraendert sein:

```text
00-ap1-cluster-collect.sh
01-pve-info.sh
02-pve-cluster.sh
03-pve-ha.sh
04-pve-storage.sh
05-pve-network.sh
06-pve-ops.sh
07-ceph-status.sh
08-ceph-topology.sh
09-ceph-pools.sh
10-ceph-capacity.sh
11-ceph-perf.sh
12-ceph-recovery.sh
90-ap1-merge.sh
lib/ap1-csv-common.sh
lib/ap1-json.pl
```

Die Build-Pruefung vergleicht SHA-256 dieser Dateien gegen die V0.4.2-Ausgangsbasis. Das Ergebnis wird vor Paketierung validiert.

## Verifizierte SHA-256-Pruefung

| Datei | SHA-256 V0.5 / V0.4.2 | Ergebnis |
|---|---|---|
| `00-ap1-cluster-collect.sh` | `288b8e944d018947f24dc80d2e3e065fdadd031bc9df3a8c8cc3aba7adef80a8` | OK |
| `01-pve-info.sh` | `1b7505a9b74206ab78e8098bde931467814a4b42ef9c484cae41d4917642c7ea` | OK |
| `02-pve-cluster.sh` | `e0d26f89e15afef1bfef476e375bd0ed63e22c5235df407746b5b3fa51f41a98` | OK |
| `03-pve-ha.sh` | `601675ccf3fe97fe264f8074b6000eae78a759ef1c0fbff934b9ba58eb0e623a` | OK |
| `04-pve-storage.sh` | `cba1a49848ce4e9b40cc3d8073b395d148e2ac388178ef64b638f5150fabbb7a` | OK |
| `05-pve-network.sh` | `216705eb4eb12a5eb82623c08789e544b58c0d23689139385dc091124695ca90` | OK |
| `06-pve-ops.sh` | `9628e6cb5c934b13651e87dccfe1b81c2872566eea2ed34a462c7dfbf00b0622` | OK |
| `07-ceph-status.sh` | `a3a838bfb5bc739db6fc23895addeee018878947389d81c8ec132730b70cc170` | OK |
| `08-ceph-topology.sh` | `b5e07823837fbf3b1e639f7083cf0102944b9f8228f5e76eed34848d2792a978` | OK |
| `09-ceph-pools.sh` | `5c745de865d55e8614b2b8ad3f6de1de717df44c9f0750e3b6a8b66b3a26b9d0` | OK |
| `10-ceph-capacity.sh` | `007e1921df26196026e8947ef1427a86dd11fcab833e6898a198f41d3a294ad7` | OK |
| `11-ceph-perf.sh` | `4c9cb1277c0275d71af1572300b3776fee856ce4c55f754015def4221ac3dc1a` | OK |
| `12-ceph-recovery.sh` | `f82705642069dcbeea46278c78a1eda105bfbbe0f9676d4bd25c6438d5e0a134` | OK |
| `90-ap1-merge.sh` | `18eff362269aee8a3f96c30b47b32cfc3e3dee3780fdf8eed7ccc460254c955c` | OK |
| `lib/ap1-csv-common.sh` | `0e39369f2e1ea06c335f84f0edec2e53c0efa5867b46306a6b684c5f6352efab` | OK |
| `lib/ap1-json.pl` | `f3a08a735b2e340dc0eb1003e007c6da403741228aa0d0be17ceeb0abf4f1e34` | OK |

Alle aufgefuehrten geerbten Scripts/Helfer wurden als byte-identisch verifiziert.
