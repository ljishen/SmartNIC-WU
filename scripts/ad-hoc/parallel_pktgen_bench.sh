#!/usr/bin/env bash
#
# Before running this script, make sure you have configured both the host and
# the BlueField card following the description on:
# https://github.com/ljishen/SmartNIC-WU/tree/main/scripts/pktgen_bench

set -eumo pipefail

info() {
  echo "[$(date --iso-8601=ns)]" "$@"
}

PKT_SIZE=1024
OUTPUT_DIR="$PWD/results/"

mkdir -p "$OUTPUT_DIR"

PID_ARR=()

BLUEFIELD_OUTPUT_FILE="$OUTPUT_DIR"/parallel_pktgen_bench_${PKT_SIZE}bytes_bluefield2.log
ssh ubuntu@192.168.100.2 \
  sudo "\$HOME"/SmartNIC-WU/scripts/pktgen_bench/xmit_multiqueue.sh \
  -i p0 -d 10.10.1.2 -s "$PKT_SIZE" -e 20 -t "\$(nproc)" -b 25 \
  >"$BLUEFIELD_OUTPUT_FILE" 2>&1 &
PID_ARR+=($!)
echo "PID of the host process ${PID_ARR[-1]}"

HOST_OUTPUT_FILE="$OUTPUT_DIR"/parallel_pktgen_bench_${PKT_SIZE}bytes_host.log
# shellcheck disable=SC2024
sudo F_THREAD=32 "$HOME"/SmartNIC-WU/scripts/pktgen_bench/xmit_multiqueue.sh \
  -i ens5f0 -d 10.10.1.2 -s "$PKT_SIZE" -e 20 -t 5 -b 25 \
  >"$HOST_OUTPUT_FILE" 2>&1 &
PID_ARR+=($!)
echo "PID of the BlueField process ${PID_ARR[-1]}"

echo
for pid in "${PID_ARR[@]}"; do
  wait "$pid"
  info "$pid" "has completed"
done


TOTAL="$(grep -oP "[\d.]+(?=Mb/sec)" "$BLUEFIELD_OUTPUT_FILE" \
  | awk '{ sum += $1 } END { print sum }')"
printf "\\n\\nTotal: %s Mb/sec\\n" "$TOTAL" >> "$BLUEFIELD_OUTPUT_FILE"

TOTAL="$(grep -oP "[\d.]+(?=Mb/sec)" "$HOST_OUTPUT_FILE" \
  | awk '{ sum += $1 } END { print sum }')"
printf "\\n\\nTotal: %s Mb/sec\\n" "$TOTAL" >> "$HOST_OUTPUT_FILE"


echo
info "Done!"
