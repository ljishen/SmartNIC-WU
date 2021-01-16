These jobfiles are directly executable with the platform compatible version of stress-ng (x86_64 or aarch64).
```bash
$ ./filename.job
```
It works by creating a slightly complex shebang in the files that uses the `awk` as the command executor. Therefore, if your machine does not have `awk` installed, you may end up with running these job files manually with the compatible stress-ng (in the `packages` directory):
```bash
$ # create a directory for stress-ng temporary files
$ mkdir -p /tmp/stress-ng
$
$ stress-ng --job ./filename.job
```
