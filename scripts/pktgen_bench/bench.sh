#!/usr/bin/env bash

set -euo pipefail

# You can change the following parameters as needed.
# --------------------------
IFNAME=ens1f1
PKT_SIZE=60 # in bytes
RUNTIME=20  # in seconds

ARR_CLONE_SKB=({0..25..5})
ARR_BURST=(1 {5..25..5})
ARR_THREADS=({1..10})

ROUNDS_PER_TEST=3
OUTPUT_DIR="./results"
# --------------------------

if ! [[ -d /sys/class/net/"$IFNAME" ]]; then
  echo "[ERROR] network device $IFNAME is not available" >&2
  exit 1
fi

operstate="$(cat /sys/class/net/$IFNAME/operstate)"
if [[ "$operstate" != "up" ]]; then
  echo "[ERROR] network device $IFNAME is $operstate" >&2
  exit 1
fi

function get_date() {
  date --iso-8601=seconds
}


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OUTPUT_FILE="${OUTPUT_DIR}/pkt_size_${PKT_SIZE}bytes.data"

mkdir -p "$OUTPUT_DIR"

got_device_info=false

printf "# Network Device Information" > "$OUTPUT_FILE"

if command -v lshw >/dev/null 2>&1; then
  {
    printf ' (via lshw)\n#\n'
    sudo lshw -class network \
      | awk -v ifname="$IFNAME" '
          BEGIN { FS="\n"; RS="\*-network:[[:digit:]]*" }
          $0 ~ ifname { print $0 }
      ' \
      | sed '/^[[:space:]]*$/d' \
      | sed 's/^ */# /'
    echo "#"
  } >> "$OUTPUT_FILE"
  got_device_info=true
fi

if [[ "$got_device_info" != true ]] \
  && command -v ethtool >/dev/null 2>&1; then
  {
    printf ' (via ethtool)\n#\n'
    sudo ethtool "$IFNAME" | sed 's/^/# /'
    echo "#"
  } >> "$OUTPUT_FILE"
  got_device_info=true
fi

if [[ "$got_device_info" != true ]]; then
  printf '\n#\n' >> "$OUTPUT_FILE"
  echo '[WARN] need either "lshw" or "ethtool" to get better device information.' >&2
fi

{
  printf '# Device speed: %d Mbit/s\n' "$(cat /sys/class/net/$IFNAME/speed)"
  printf '# Device mtu: %d bytes\n' "$(cat /sys/class/net/$IFNAME/mtu)"
  printf '# Device tx_queue_len: %d\n#\n' "$(cat /sys/class/net/$IFNAME/tx_queue_len)"
  printf '# Start of test: %s\n\n' "$(get_date)"
} >> "$OUTPUT_FILE"

printf 'THREADS\tCLONE_SKB\tBURST\tTHROUGHPUT (Mb/sec)\tSTD\n' >> "$OUTPUT_FILE"

for t in "${ARR_THREADS[@]}"; do
  for c in "${ARR_CLONE_SKB[@]}"; do
    for b in "${ARR_BURST[@]}"; do
      echo "[$(get_date)][INFO] running" \
           "THREADS=$t (${ARR_THREADS[0]}..${ARR_THREADS[-1]})," \
           "CLONE_SKB=$c (${ARR_CLONE_SKB[0]}..${ARR_CLONE_SKB[-1]})," \
           "BURST=$b (${ARR_BURST[0]}..${ARR_BURST[-1]})"

      records=()
      for _ in $(seq "$ROUNDS_PER_TEST"); do
        res=$(
          "$SCRIPT_DIR"/xmit_multiqueue.sh \
            -i "$IFNAME" \
            -e "$RUNTIME" \
            -s "$PKT_SIZE" \
            -t "$t" \
            -c "$c" \
            -b "$b" 2>&1 \
              | grep -oP "\d+(?=Mb/sec)" \
              | awk '{ sum += $1 } END { print sum }'
          )
        records+=("$res")
      done

      printf '%s\n' "${records[@]}" | awk \
        -v t="$t" \
        -v c="$c" \
        -v b="$b" \
        '
          {
            sum += $0
            sum_sq += $0 ^ 2
          }

          END {
            printf("%d\t%d\t%d\t%.2f\t%.2f\n",
              t, c, b,
              sum / NR,
              sqrt(sum_sq / NR - (sum / NR) ^ 2))
          }
        ' >> "$OUTPUT_FILE"
    done
  done
done

printf '\n# End of test: %s' "$(get_date)"
echo "[$(get_date)][INFO] completed!"
