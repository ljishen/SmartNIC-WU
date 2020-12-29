pktgen.c:
  This file is modified based on the copy from the Linux kernel source v5.4.44. The only modification is to undefine the CONFIG_XFRM macro.

build\\\*\*\\pktgen.ko:
  These files are created by calling `make` from within the build OS.

  For example, `build/5.4.44-mlnx.14.gd7fb187/pktgen.ko` is built within the [BlueField-2 Ubuntu Server 20.04 (version 5.1-2.3.7.1-2)](https://developer.nvidia.com/networking/doca):
  ```bash
  $ uname --all
  Linux localhost.localdomain 5.4.44-mlnx.14.gd7fb187 #1 SMP PREEMPT Tue Sep 15 16:18:01 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux
  ```
