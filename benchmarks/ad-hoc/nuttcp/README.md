These scripts are for testing throughput (client sends, server receives) using [the same system setup as with iperf3 for hosts and the BlueField-2 card](https://github.com/ljishen/SmartNIC-WU/blob/main/benchmarks/ad-hoc/iperf3/README.md), except that they uses [nuttcp](https://www.nuttcp.net/Welcome%20Page.html).

---

The test between two r7527 hosts uses the UDP protcol, and the best result I've seen is 99212.3 Mbps, which has maximized the theoretical 100 Gbps network.

The test between a host and the BlueField-2 card uses the TCP protocol, as the throughput seen is better than using the UDP protocol (~32000 Mbps). The best result in this test is 51638.9 Mbps, reaching a half of the theoretical bandwidth.

[Note] the nuttcp version used in above tests is 8.2.2.
