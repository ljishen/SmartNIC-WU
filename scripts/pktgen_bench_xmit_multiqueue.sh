#!/usr/bin/env bash
#
# Multiqueue: Using pktgen threads for sending on multiple CPUs
#  * adding devices to kernel threads
#  * notice the naming scheme for keeping device names unique
#  * nameing scheme: dev@thread_number
#  * flow variation via random UDP source port

set -euo pipefail

basedir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# shellcheck source=/dev/null
source "${basedir}"/functions.sh
root_check_run_with_sudo "$@"

# shellcheck source=/dev/null
source "${basedir}"/parameters.sh

# Base Config
DELAY="0"        # Zero means max speed

# Flow variation random source port between min and max
UDP_SRC_MIN=9
UDP_SRC_MAX=109

# (example of setting default params in your script)
if [[ -n "$DEST_IP" ]]; then
  validate_addr"$IP6" "$DEST_IP"
  read -r DST_MIN DST_MAX <<< "$(parse_addr"$IP6" "$DEST_IP")"
fi
if [[ -n "$DST_PORT" ]]; then
  read -r UDP_DST_MIN UDP_DST_MAX <<< "$(parse_ports "$DST_PORT")"
  validate_ports "$UDP_DST_MIN" "$UDP_DST_MAX"
fi

# General cleanup everything since last run
pg_ctrl "reset"

# The device name is extended with @name, using thread number to
# make then unique, but any name will do.
function get_thread_dev() {
  local thread=$1
  echo "$DEV@$thread"
}

# Threads are specified with parameter -t value in $THREADS
for ((thread = "$F_THREAD"; thread <= "$L_THREAD"; thread++)); do
  dev=$(get_thread_dev $thread)

  # Add remove all other devices and add_device $dev to thread
  pg_thread $thread "rem_device_all"
  pg_thread $thread "add_device" "$dev"

  # Notice config queue to map to cpu (mirrors smp_processor_id())
  # It is beneficial to map IRQ /proc/irq/*/smp_affinity 1:1 to CPU number
  pg_set "$dev" "flag QUEUE_MAP_CPU"

  # Base config of dev
  pg_set "$dev" "count $COUNT"
  pg_set "$dev" "clone_skb $CLONE_SKB"
  pg_set "$dev" "pkt_size $PKT_SIZE"
  pg_set "$dev" "delay $DELAY"

  # Flag example disabling timestamping
  pg_set "$dev" "flag NO_TIMESTAMP"

  # Destination
  # shellcheck disable=SC2153
  pg_set "$dev" "dst_mac $DST_MAC"
  pg_set "$dev" "dst${IP6}_min $DST_MIN"
  pg_set "$dev" "dst${IP6}_max $DST_MAX"

  if [[ -n "$DST_PORT" ]]; then
    # Single destination port or random port range
    pg_set "$dev" "flag UDPDST_RND"
    pg_set "$dev" "udp_dst_min $UDP_DST_MIN"
    pg_set "$dev" "udp_dst_max $UDP_DST_MAX"
  fi

  # Setup random UDP port src range
  pg_set "$dev" "flag UDPSRC_RND"
  pg_set "$dev" "udp_src_min $UDP_SRC_MIN"
  pg_set "$dev" "udp_src_max $UDP_SRC_MAX"
done

function stop_and_print_results() {
  pg_ctrl "stop"
  printf -- "\\n-------------------- RESULTS --------------------\\n"
  for ((thread = "$F_THREAD"; thread <= "$L_THREAD"; thread++)); do
    dev=$(get_thread_dev $thread)
    grep -A2 "Result:" "$PROC_DIR/$dev" 2>&1 | sed "s/^/[IFNAME: $dev] /"
  done
}

# start_run
echo
echo "Running... ctrl^C to stop"
pg_ctrl "start" &
trap_exit_funcs+=(stop_and_print_results)

while :; do
  sleep "$INTERVAL"
  echo
  for ((thread = "$F_THREAD"; thread <= "$L_THREAD"; thread++)); do
    dev=$(get_thread_dev $thread)
    awk -v dev="$dev" -v thread="$thread" -v F_THREAD="$F_THREAD" '
      BEGIN { in_current = 0 }
      $0 ~ /^Result:/ { exit }
      $0 ~ /^Current:/ {
        in_current = 1
        next
      }
      in_current == 1 {
        num = split($0, arr, " ")
        for (i = 1; i <= num; i+=2) {
          key = sub(/:$/, "", arr[i])
          data[arr[i]] = arr[i + 1]
        }
      }
      END {
        if (thread == F_THREAD) {
          printf "IFNAME "
          for (key in data)
            printf "%s ", toupper(key)
          print ""
        }

        printf "%s ", dev
        for (key in data)
          printf "%s ", data[key]
        print ""
      }
    ' "$PROC_DIR/$dev"
  done | column -t
done
