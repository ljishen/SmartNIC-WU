#!/usr/bin/env bash

set -euo pipefail

# You can change the following parameters as needed.
# --------------------------
readonly IFNAME=ens1f1
readonly PKT_SIZE=60 # in bytes
readonly RUNTIME=20  # in seconds

readonly ROUNDS_PER_TEST=3
readonly OUTPUT_DIR="./results"

# The first step of testing is to evaluate the least value of
# THREADS, CLONE_SKB, and BURST that can achieve the maximum
# throughput of the network device.
# Once the three numbers are identified, we can evaluate how
# various delays added between packets would deviate the throughput
# from the maximum capacity. We perform this step by fixing the
# value of CLONE_SKB and BURST identified in the first step, but
# varying the value of DELAY and THREADS. Increasing threads in the
# test can evaluate whether or how much the throughput can be
# improved under a given packet delay.
#
# ===== STEP ONE =====
readonly ARR_DELAY=(0)
readonly ARR_THREADS=({1..10})
readonly ARR_CLONE_SKB=({0..25..5})
readonly ARR_BURST=(1 {5..25..5})
# ===================
#
# ===== STEP TWO =====
# exmple delays for evaluation
# ARR_DELAY=(0 125 250 500 1000 2000 4000 8000 16000)
# ARR_THREADS=({1..10})
# ARR_CLONE_SKB=(20)  # update this value
# ARR_BURST=(20)      # update this value
# ====================

# if true, write debug output to $OUTPUT_DIR/debug.log
readonly DEBUG=false
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

readonly OUTPUT_FILE="${OUTPUT_DIR}/pkt_size_${PKT_SIZE}bytes.data"
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "[ERROR] we don't want to overwrite the existing file $OUTPUT_FILE" >&2
  exit 2
else
  mkdir -p "$OUTPUT_DIR"
fi

function get_date() {
  date --iso-8601=seconds
}

function print_separator() {
  echo "# ========================================"
}

got_device_info=false

printf '# Network Device Information' > "$OUTPUT_FILE"

if command -v lshw >/dev/null 2>&1; then
  {
    echo " (via lshw)"
    print_separator
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
    echo " (via ethtool)"
    print_separator
    sudo ethtool "$IFNAME" | sed 's/^/# /'
    echo "#"
  } >> "$OUTPUT_FILE"
  got_device_info=true
fi

if [[ "$got_device_info" != true ]]; then
  {
    echo
    print_separator
  } >> "$OUTPUT_FILE"
  echo '[WARN] need either "lshw" or "ethtool" to get better device information.' >&2
fi

{
  printf '# Device speed: %d Mbit/s\n' "$(cat /sys/class/net/$IFNAME/speed)"
  printf '# Device mtu: %d bytes\n' "$(cat /sys/class/net/$IFNAME/mtu)"
  printf '# Device tx_queue_len: %d\n' "$(cat /sys/class/net/$IFNAME/tx_queue_len)"
  print_separator
} >> "$OUTPUT_FILE"

{
  printf '#\n# CPU Information\n'
  print_separator
  # shellcheck disable=SC2016,SC1004
  find /sys/devices/system/cpu -type d -name "cpu[0-9]*" \
    | sort --version-sort \
    | xargs -I '{}' sh -c '
        printf "%s: socket %d, %d KHz\\n" \
          "$(basename {})" \
          "$(cat {}/topology/physical_package_id)" \
          "$(cat {}/cpufreq/cpuinfo_max_freq)"' \
    | sed 's/^/# /'
  print_separator

  printf '#\n# Memory Information\n'
  print_separator
  if [[ -d /sys/devices/system/node ]]; then
    cat /sys/devices/system/node/node*/meminfo | grep -i MemTotal
  else
    head --lines=3 /proc/meminfo
  fi | sed 's/^/# /'
  print_separator

  printf '#\n# Start of test: %s\n\n' "$(get_date)"
} >> "$OUTPUT_FILE"


readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
debug_command="cat"
if [[ "$DEBUG" == true ]]; then
  debug_command="tee $OUTPUT_DIR/debug.log"
fi

printf 'DELAY (ns)\tTHREADS\tCLONE_SKB\tBURST\tTHROUGHPUT (Mb/sec)\tSTD\n' >> "$OUTPUT_FILE"

for d in "${ARR_DELAY[@]}"; do
  for t in "${ARR_THREADS[@]}"; do
    for c in "${ARR_CLONE_SKB[@]}"; do
      for b in "${ARR_BURST[@]}"; do
        echo "[$(get_date)][INFO] running" \
             "DELAY=$d (${ARR_DELAY[0]}..${ARR_DELAY[-1]})," \
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
              -l "$d" \
              -t "$t" \
              -c "$c" \
              -b "$b" 2>&1 \
                | sh -c "$debug_command" \
                | grep -oP "\d+(?=Mb/sec)" \
                | awk '{ sum += $1 } END { print sum }'
            )
          records+=("$res")
        done

        printf '%s\n' "${records[@]}" | awk \
          -v d="$d" \
          -v t="$t" \
          -v c="$c" \
          -v b="$b" \
          '
            {
              sum += $0
              sum_sq += $0 ^ 2
            }

            END {
              printf("%d\t%d\t%d\t%d\t%.2f\t%.2f\n",
                d, t, c, b,
                sum / NR,
                sqrt(sum_sq / NR - (sum / NR) ^ 2))
            }
          ' >> "$OUTPUT_FILE"
      done
    done
  done
done

printf '\n# End of test: %s' "$(get_date)" >> "$OUTPUT_FILE"
echo "[$(get_date)][INFO] completed!"
