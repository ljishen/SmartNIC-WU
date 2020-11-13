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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OUTPUT_FILE="${OUTPUT_DIR}/pkt_size_${PKT_SIZE}bytes.data"

mkdir -p "$OUTPUT_DIR"

got_device_info=false

printf "# Network Device Information" > "$OUTPUT_FILE"

if command -v lshw >/dev/null 2>&1; then
  printf " (via lshw)\\n#\\n" >> "$OUTPUT_FILE"
  sudo lshw -class network \
    | awk -v ifname="$IFNAME" '
        BEGIN { FS="\n"; RS="\*-network:[[:digit:]]" }
        $0 ~ ifname { print $0 }
    ' \
    | sed '/^[[:space:]]*$/d' \
    | sed 's/^ */# /' >> "$OUTPUT_FILE"
  got_device_info=true
fi

if [[ "$got_device_info" != true ]] \
  && command -v ethtool >/dev/null 2>&1; then
  printf " (via ethtool)\\n#\\n" >> "$OUTPUT_FILE"
  sudo ethtool "$IFNAME" | sed 's/^/# /' >> "$OUTPUT_FILE"
  got_device_info=true
fi

if [[ "$got_device_info" != true ]]; then
  printf " (not available)\\n#\\n" >> "$OUTPUT_FILE"
  echo "[WARN] need either \"lshw\" or \"ethtool\" to get network device information" >&2
fi

echo >> "$OUTPUT_FILE"

printf "CLONE_SKB\\tBURST\\tTHREADS\\tTHROUGHT (Mb/sec)\\n" >> "$OUTPUT_FILE"

for c in "${ARR_CLONE_SKB[@]}"; do
  for b in "${ARR_BURST[@]}"; do
    for t in "${ARR_THREADS[@]}"; do
      echo "[INFO] running" \
           "CLONE_SKB=$c (${ARR_CLONE_SKB[0]}..${ARR_CLONE_SKB[-1]})," \
           "BURST=$b (${ARR_BURST[0]}..${ARR_BURST[-1]})," \
           "THREADS=$t (${ARR_THREADS[0]}..${ARR_THREADS[-1]})"

      res_total=0
      for _ in $(seq "$ROUNDS_PER_TEST"); do
        res=$(
          "$SCRIPT_DIR"/xmit_multiqueue.sh \
            -i "$IFNAME" \
            -e "$RUNTIME" \
            -s "$PKT_SIZE" \
            -c "$c" \
            -b "$b" \
            -t "$t" 2>&1 \
              | grep -oP "\d+(?=Mb/sec)" \
              | awk '{ sum += $1 } END { print sum }'
          )
          (( res_total += res ))
      done

      awk \
        -v c="$c" \
        -v b="$b" \
        -v t="$t" \
        -v res_total="$res_total" \
        -v rounds="$ROUNDS_PER_TEST" \
        ' BEGIN { printf("%s\t%s\t%s\t%s\n", c, b, t, res_total / rounds) } ' \
        >> "$OUTPUT_FILE"
    done
  done
done

echo "[INFO] completed!"
