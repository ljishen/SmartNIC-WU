#!/usr/bin/env bash

set -euo pipefail

# You can change the following parameters as needed.
# --------------------------
readonly RUNTIME=20     # in seconds

readonly ROUNDS_PER_TEST=3
readonly OUTPUT_DIR="$PWD/results"

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
# readonly ARR_DELAY=(0 125 250 500 1000 2000 4000 8000 16000)
# IFS=' ' read -ra ARR_THREADS <<< "$(seq -s ' ' 1 "$(nproc)")"
# readonly ARR_CLONE_SKB=(0)  # update this value
# readonly ARR_BURST=(5)      # update this value
# ====================

# if true, write debug output to $OUTPUT_DIR/debug.log
readonly DEBUG=false
# --------------------------

err() {
  local -ir exit_status="$1"
  shift
  printf "\\033[1;31m[ERROR] %s\\033[0m\\n" "$*" >&2
  exit "$exit_status"
}


if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 ifname pkt_size"
  exit
fi

if [[ "$EUID" -ne 0 ]]; then
  err 1 "This program should be run as root"
fi

readonly IFNAME="$1"
readonly PKT_SIZE="$2"  # in bytes

if ! [[ -d /sys/class/net/"$IFNAME" ]]; then
  err 2 "Network device $IFNAME is not available."
fi

if ! [[ "$PKT_SIZE" =~ ^[0-9]+$ ]]; then
  err 2 "pkt_size is not a positive number."
fi

readonly IFOPSTATE="$(cat /sys/class/net/"$IFNAME"/operstate)"
if [[ "$IFOPSTATE" != "up" ]]; then
  err 3 "Network device $IFNAME is $IFOPSTATE."
fi

if ! command -v "sar" >/dev/null 2>&1; then
  err 4 "Please install the 'sysstat' package for system activity data collection."
fi


now() {
  date --iso-8601=ns
}

info() {
  echo "[$(now)][INFO] $*"
}

delay_test() {
  local -i delay
  for delay in "${ARR_DELAY[@]}"; do
    if (( delay > 0 )); then
      echo true
      break
    fi
  done
  echo false
}

if [[ "$(delay_test)" == true ]]; then
  filename_extra="_delays"
fi
readonly OUTPUT_DATA_FILE="${OUTPUT_DIR}/pkt_size_${PKT_SIZE}bytes${filename_extra:-}.dat"
readonly OUTPUT_LOG_FILE="${OUTPUT_DATA_FILE%.*}.log"
readonly OUTPUT_SYS_ACTIVITY_FILE="${OUTPUT_DATA_FILE%.*}_sys_activity.dat"
if [[ -f "$OUTPUT_DATA_FILE" ]]; then
  err 3 "We don't want to overwrite the existing file $OUTPUT_DATA_FILE"
else
  mkdir -p "$OUTPUT_DIR"
  rm --force "$OUTPUT_LOG_FILE" "$OUTPUT_SYS_ACTIVITY_FILE"
  info "OUTPUT_DIR: $OUTPUT_DIR"
fi

separate() {
  echo "# ========================================"
}

GOT_NIC_INFO=false
printf '# Network Device Information' > "$OUTPUT_DATA_FILE"

get_nic_info_lshw() {
  if command -v lshw >/dev/null 2>&1; then
    {
      echo " (via lshw)"
      separate
      lshw -class network \
        | awk -v ifname="$IFNAME" '
            BEGIN { FS="\n"; RS="\*-network:[[:digit:]]*" }
            $0 ~ ifname { print $0 }
        ' \
        | sed '/^[[:space:]]*$/d' \
        | sed 's/^ */# /'
      echo "#"
    } >> "$OUTPUT_DATA_FILE"
    echo true
  fi
}
GOT_NIC_INFO=$(get_nic_info_lshw)

get_nic_info_ethtool() {
  if command -v ethtool >/dev/null 2>&1; then
    local -i exit_status=0
    local ethtool_output
    ethtool_output="$(ethtool "$IFNAME" | sed 's/^/# /')" || exit_status=$?
    # some machine may print "No data available"
    # with exit_status=75 (e.g. wlan0 on Raspberry Pi)
    if (( exit_status == 0 )); then
      {
        echo " (via ethtool)"
        separate
        echo "$ethtool_output"
        echo "#"
      } >> "$OUTPUT_DATA_FILE"
      echo true
    fi
  fi
}
if [[ "$GOT_NIC_INFO" != true ]]; then
  GOT_NIC_INFO=$(get_nic_info_ethtool)
fi

if [[ "$GOT_NIC_INFO" != true ]]; then
  {
    echo
    separate
  } >> "$OUTPUT_DATA_FILE"
  echo '[WARN] Need either "lshw" or "ethtool" to log the NIC information.' >&2
fi

{
  printf '# Device speed: %d Mbit/s\n' "$(cat /sys/class/net/"$IFNAME"/speed)"
  printf '# Device mtu: %d bytes\n' "$(cat /sys/class/net/"$IFNAME"/mtu)"
  printf '# Device tx_queue_len: %d\n' "$(cat /sys/class/net/"$IFNAME"/tx_queue_len)"
  separate
  echo "#"
} >> "$OUTPUT_DATA_FILE"


GOT_CPU_INFO=false
printf '# CPU Information' >> "$OUTPUT_DATA_FILE"

get_cpu_info_dmidecode() {
  if command -v dmidecode >/dev/null 2>&1; then
    local dmidecode_output
    # sed '$d' to delete the last line (empty line)
    dmidecode_output="$(
      dmidecode --type processor \
        | sed '/^#/d' \
        | sed 's/^/# /' \
        | sed '$d'
    )"
    if grep "Max Speed:" <<< "$dmidecode_output" >/dev/null 2>&1; then
      {
        echo " (via dmidecode)"
        separate
        echo "$dmidecode_output"
        separate
        echo "#"
      } >> "$OUTPUT_DATA_FILE"
      echo true
    fi
  fi
}
GOT_CPU_INFO=$(get_cpu_info_dmidecode)

get_cpu_info_lshw() {
  if command -v lshw >/dev/null 2>&1; then
    {
      echo " (via lshw)"
      separate
      lshw -class cpu \
        | awk '
            BEGIN { FS="\n"; RS="\*-cpu:[[:digit:]]*" }
            { print $0 }
        ' \
        | sed '/^[[:space:]]*$/d' \
        | sed 's/^ */# /'
      separate
      echo "#"
    } >> "$OUTPUT_DATA_FILE"
    echo true
  fi
}
if [[ "$GOT_CPU_INFO" != true ]]; then
  GOT_CPU_INFO=$(get_cpu_info_lshw)
fi

get_cpu_info_sysfs() {
  # the directory may not exist
  #   https://software.intel.com/sites/default/files/comment/1716807/how-to-change-frequency-on-linux-pub.txt
  if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    {
      echo " (via sysfs)"
      separate
      # shellcheck disable=SC1004
      find /sys/devices/system/cpu -type d -name "cpu[0-9]*" \
        | sort --version-sort \
        | xargs -I '{}' sh -c '
            printf "# %s: socket %d, %d KHz\\n" \
              "$(basename {})" \
              "$(cat {}/topology/physical_package_id)" \
              "$(cat {}/cpufreq/cpuinfo_max_freq)"'
      separate
      echo "#"
    } >> "OUTPUT_DATA_FILE"
    echo true
  fi
}
if [[ "$GOT_CPU_INFO" != true ]]; then
  GOT_CPU_INFO=$(get_cpu_info_sysfs)
fi

if [[ "$GOT_CPU_INFO" != true ]]; then
  {
    echo " (not available)"
    separate
    echo "#"
  } >> "$OUTPUT_DATA_FILE"
  echo '[WARN] Need either "dmidecode" or "lshw" to log the CPU information.' >&2
fi


{
  echo "# Memory Information"
  separate
  if [[ -d /sys/devices/system/node ]]; then
    cat /sys/devices/system/node/node*/meminfo | grep -i MemTotal
  else
    head --lines=3 /proc/meminfo
  fi | sed 's/^/# /'
  separate
  echo "#"

  printf '# Start of test: %s\n\n' "$(now)"
} >> "$OUTPUT_DATA_FILE"


info "Kill existing sar processes"
pkill -INT -u "$USER" sar || true
S_TIME_FORMAT=ISO sar -A -o "$OUTPUT_SYS_ACTIVITY_FILE" 5 >/dev/null 2>&1 &
SAR_PID=$!

clean_up() {
  kill -INT "$SAR_PID"
  info "Stopped the system activity data collection process (PID $SAR_PID)"
}
trap clean_up EXIT
info "Started to collect system activity data (PID $SAR_PID)"

readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DEBUG_COMMAND="cat"
if [[ "$DEBUG" == true ]]; then
  DEBUG_COMMAND="tee --append $OUTPUT_DIR/debug.log"
fi


echo
printf '"DELAY (ns)"\tTHREADS\tCLONE_SKB\tBURST\t"THROUGHPUT (Mb/sec)"\tSTD\n' >> "$OUTPUT_DATA_FILE"

for d in "${ARR_DELAY[@]}"; do
  for t in "${ARR_THREADS[@]}"; do
    for c in "${ARR_CLONE_SKB[@]}"; do
      for b in "${ARR_BURST[@]}"; do
        info "Running" \
             "DELAY=$d (${ARR_DELAY[0]}..${ARR_DELAY[-1]})," \
             "THREADS=$t (${ARR_THREADS[0]}..${ARR_THREADS[-1]})," \
             "CLONE_SKB=$c (${ARR_CLONE_SKB[0]}..${ARR_CLONE_SKB[-1]})," \
             "BURST=$b (${ARR_BURST[0]}..${ARR_BURST[-1]})" | tee --append "$OUTPUT_LOG_FILE"

        RECORDS=()
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
                | sh -c "$DEBUG_COMMAND" \
                | grep -oP "\d+(?=Mb/sec)" \
                | awk '{ sum += $1 } END { print sum }'
            )
          RECORDS+=("$res")
        done

        printf '%s\n' "${RECORDS[@]}" | awk \
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
          ' >> "$OUTPUT_DATA_FILE"
      done
    done
  done
done

printf '\n# End of test: %s\n' "$(now)" >> "$OUTPUT_DATA_FILE"
{ echo; info "Complete!"; } | tee --append "$OUTPUT_LOG_FILE"
