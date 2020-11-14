#!/usr/bin/env bash
#
# Multiqueue: Using pktgen threads for sending on multiple CPUs
#  * adding devices to kernel threads
#  * notice the naming scheme for keeping device names unique
#  * nameing scheme: dev@thread_number
#  * flow variation via random UDP source port

set -euo pipefail

readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}"/functions.sh
root_check_run_with_sudo "$@"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}"/parameters.sh

# Flow variation random source port between min and max
# discard protocol on port 9: https://en.wikipedia.org/wiki/Discard_Protocol
# See the list of well known ports:
#   https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers#Well-known_ports
readonly UDP_SRC_MIN=9
readonly UDP_SRC_MAX=109

validate_addr"$IP6" "$DEST_IP"
read -r DST_MIN DST_MAX <<< "$(parse_addr"$IP6" "$DEST_IP")"

if [[ -n "$DST_PORT" ]]; then
  read -r UDP_DST_MIN UDP_DST_MAX <<< "$(parse_ports "$DST_PORT")"
  validate_ports "$UDP_DST_MIN" "$UDP_DST_MAX"
fi

# General cleanup everything since last run
newline_for_debug_output
pg_ctrl "reset"

# The device name is extended with @name, using thread number to
# make then unique, but any name will do.
function get_thread_dev() {
  local thread=$1
  echo "$DEV@$thread"
}

for (( thread = "$F_THREAD"; thread <= "$L_THREAD"; thread++ )); do
  dev=$(get_thread_dev $thread)

  # Add remove all other devices and add_device $dev to thread
  pg_thread $thread "rem_device_all"
  pg_thread $thread "add_device" "$dev"

  # Notice config queue to map to cpu (mirrors smp_processor_id())
  # It is beneficial to map IRQ /proc/irq/*/smp_affinity 1:1 to CPU number
  pg_set "$dev" "flag QUEUE_MAP_CPU"

  # Base config of dev
  pg_set "$dev" "count $COUNT"
  pg_set "$dev" "pkt_size $PKT_SIZE"
  pg_set "$dev" "delay $DELAY"

  # Flag example disabling timestamping
  pg_set "$dev" "flag NO_TIMESTAMP"

  # Destination
  # shellcheck disable=SC2153
  pg_set "$dev" "dst_mac $DST_MAC"
  pg_set "$dev" "dst${IP6}_min $DST_MIN"
  pg_set "$dev" "dst${IP6}_max $DST_MAX"

  # Setup random UDP port src range
  pg_set "$dev" "flag UDPSRC_RND"
  pg_set "$dev" "udp_src_min $UDP_SRC_MIN"
  pg_set "$dev" "udp_src_max $UDP_SRC_MAX"

  if [[ -n "$DST_PORT" ]]; then
    # Single destination port or random port range
    pg_set "$dev" "flag UDPDST_RND"
    pg_set "$dev" "udp_dst_min $UDP_DST_MIN"
    pg_set "$dev" "udp_dst_max $UDP_DST_MAX"
  fi

  pg_set "$dev" "xmit_mode $XMIT_MODE"
  if [[ "$XMIT_MODE" == "$XMIT_MODE_START_XMIT" ]]; then
    pg_set "$dev" "clone_skb $CLONE_SKB"

    # Setup burst
    pg_set "$dev" "burst $BURST"
  fi
done

function print_results() {
  printf -- '\n-------------------- RESULTS --------------------\n'
  for (( thread = "$F_THREAD"; thread <= "$L_THREAD"; thread++ )); do
    dev=$(get_thread_dev $thread)
    grep -A2 "Result:" "$PROC_DIR/$dev" 2>&1 | sed "s/^/[IFNAME: $dev] /"
  done
}

function print_summary() {
  echo
  for (( thread = "$F_THREAD"; thread <= "$L_THREAD"; thread++ )); do
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
          # remove the ending colon
          key = substr(arr[i], 1, length(arr[i]) - 1)
          data[key] = arr[i + 1]
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
}

function setup_timeout() {
  if (( TIMEOUT  > 0 )); then
    sleep "$TIMEOUT"

    # the first kill can be futile if at the same time a new
    # sleep interval is brought up.
    pkill -INT --parent "$$"
    pkill -INT --parent "$$"
  fi
}

# start_run
echo
if (( INTERVAL > 0 )); then
  echo "Output device summary every $INTERVAL seconds."
fi
printf "Running (PID=%d)" "$$"
if (( TIMEOUT > 0 )); then
  printf " up to %d seconds" "$TIMEOUT"
fi
echo "... Ctrl-C to stop."

newline_for_debug_output
pg_ctrl "start" &
exit_trap_funcs+=(print_results)

setup_timeout &

if (( INTERVAL > 0 )); then
  while :; do
    sleep "$INTERVAL"
    print_summary
  done
else
  sleep 99999999
fi
