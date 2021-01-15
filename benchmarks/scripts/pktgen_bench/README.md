## Tests on x86_64 Hosts

To obtain more accurate results, it is beneficial to

1. map IRQs of the network device `/proc/irq/*/smp_affinity` (or `/proc/irq/*/smp_affinity_list`) 1:1 to the CPUs of the device. This reduces cache bouncing when freeing skbs. For Mellanox's adapters, you can use the [set_irq_affinity.sh](https://github.com/Mellanox/mlnx-tools/blob/master/ofed_scripts/set_irq_affinity.sh) script to automate the IRQ affinity configuration for the device:
    ```bash
    sudo systemctl stop irqbalance
    sudo mlnx-tools/ofed_scripts/set_irq_affinity.sh <interface or IB device>
    ```
2. pktgen [add_device](https://www.kernel.org/doc/Documentation/networking/pktgen.txt) to the kernel threads associated with the same NUMA node of the network device. To make this work, you can use the `-f` option (in [xmit_multiqueue.sh](./xmit_multiqueue.sh)), or set the environment variable `F_THREAD` to offset the starting CPU ID (instead of 0) of the test.


#### References

- [How to Tune Your Linux Server for Best Performance Using the mlnx_tune Tool](https://community.mellanox.com/s/article/How-to-Tune-Your-Linux-Server-for-Best-Performance-Using-the-mlnx-tune-Tool)
- [mlnx-tools from Github](https://github.com/Mellanox/mlnx-tools): get the `set_irq_affinity.sh` script from this repository
