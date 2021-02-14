These scripts are for testing throughput between two r7525 nodes from CloudLab using the BlueField-2 network cards. The BlueField-2 card is installed on NUMA node 1 of the host (two NUMA nodes 0 and 1).

For the test between two hosts, we need to first configure the IRQ affinity for the network adapter using the `set_irq_affinity_bynode.sh` script from the repository [Mellanox/mlnx-tools](https://github.com/Mellanox/mlnx-tools), then enable the jumbo frame on the corresponding network interface.

For the test between a host and the BlueOS (Ubuntu 20.04.1 LTS) of the BlueField-2 card, we don't need to configure the IRQ affinity for the card, but still be necessary for the host. The jumbo frame should also be enabled on both sides as well.

Additionally, the following configuration should be added to `/etc/sysctl.conf` for the BlueField-2 card, followed by running `sudo sysctl -p` to apply the changes.
```bash
# allow testing with 2GB buffers
net.core.rmem_max = 2147483647
net.core.wmem_max = 2147483647
# allow auto-tuning up to 2GB buffers
net.ipv4.tcp_rmem = 4096 87380 2147483647
net.ipv4.tcp_wmem = 4096 65536 2147483647
```

---

My recent test results is ~95 Gbits/sec between two hosts, and ~30 Gbits/sec between a host and the card, using iperf 3.7 (cJSON 1.5.2).

Following is the `uname -a` information of the systems under test:

BlueOS:
```bash
Linux localhost.localdomain 5.4.0-1007-bluefield #10-Ubuntu SMP PREEMPT Fri Nov 27 14:48:47 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux
```

r7525:
```bash
Linux node-1.bluefield2.ucsc-cmps107-pg0.clemson.cloudlab.us 5.4.0-51-generic #56-Ubuntu SMP Mon Oct 5 14:28:49 UTC 2020 x86_64 x86_64 x86_64 GNU/Linux
```
