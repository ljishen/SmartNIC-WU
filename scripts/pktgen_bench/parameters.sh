#!/usr/bin/env bash
# Common parameter parsing for pktgen scripts

set -euo pipefail

# https://marc.info/?l=linux-netdev&m=145221897804178&w=2
export XMIT_MODE_QUEUE_XMIT="queue_xmit"
export XMIT_MODE_START_XMIT="start_xmit"

function usage() {
  echo
  echo "Usage: $0 -i ethX [OPTIONS]"
  echo "  -i : (\$DEV)       output interface/device (required)"
  echo "  -d : (\$DEST_IP)   destination IP. CIDR (e.g. 198.18.0.0/15) is also allowed"
  echo "  -6 : (\$IP6)       IPv6"
  echo "  -a : (\$DST_MAC)   destination MAC-addr"
  echo "  -p : (\$DST_PORT)  destination PORT range (e.g. 433-444) is also allowed"
  echo "  -c : (\$CLONE_SKB) SKB clones send before alloc new SKB (default 0)"
  echo "  -b : (\$BURST)     HW level bursting of SKBs (>= 1, default 1)"
  echo "  -m : (\$XMIT_MODE) can be <$XMIT_MODE_START_XMIT|$XMIT_MODE_QUEUE_XMIT> (default $XMIT_MODE_START_XMIT)"
  echo "  -s : (\$PKT_SIZE)  packet size in bytes (>= 14 + 20 + 8, default 60)"
  echo "  -t : (\$THREADS)   threads to start"
  echo "  -f : (\$F_THREAD)  index of first thread (zero indexed CPU number)"
  echo "  -n : (\$COUNT)     num messages to send per thread, 0 means indefinitely"
  echo "  -l : (\$DELAY)     add delay between packets in nanoseconds (default 0)"
  echo "  -g : (\$INTERVAL)  interval of device summary in seconds (default 0, disabled)"
  echo "  -e : (\$TIMEOUT)   run with a time limit in seconds, 0 means indefinitely"
  echo "  -v : (\$VERBOSE)   verbose"
  echo "  -x : (\$DEBUG)     debug"
  echo
}

##  --- Parse command line arguments / parameters ---
while getopts ":i:d:6a:p:c:b:m:s:t:f:n:l:g:e:vxh" option; do
  # shellcheck disable=SC2034
  case $option in
    i  ) DEV=$OPTARG ;;
    d  ) DEST_IP=$OPTARG ;;
    6  ) IP6=6 ;;
    a  ) DST_MAC=$OPTARG ;;
    p  ) DST_PORT=$OPTARG ;;
    c  ) CLONE_SKB=$OPTARG ;;
    b  ) BURST=$OPTARG ;;
    m  ) XMIT_MODE=$OPTARG ;;
    s  ) PKT_SIZE=$OPTARG ;;
    t  ) THREADS=$OPTARG ;;
    f  ) F_THREAD=$OPTARG ;;
    n  ) COUNT=$OPTARG ;;
    l  ) DELAY=$OPTARG ;;
    g  ) INTERVAL=$OPTARG ;;
    e  ) TIMEOUT=$OPTARG ;;
    v  ) VERBOSE=true ;;
    x  ) DEBUG=true ;;
    h  )
      usage
      exit
      ;;
    \? )
      usage
      err 2 "Invalid option: -$OPTARG"
      ;;
    :  )
      usage
      err 2 "Option -$OPTARG requires an argument."
      ;;
    *  )
      usage
      exit
  esac
done
shift "$(( OPTIND - 1 ))"

all_params=()
function add_to_export() {
  local def_val="${2:-}"
  export "$1"="${!1:-$def_val}"
  all_params+=("$1")
}

add_to_export DEV
if [[ -z "$DEV" ]]; then
  usage
  err 2 "Please specify output device"
fi

add_to_export IP6
add_to_export DST_PORT

add_to_export CLONE_SKB 0
add_to_export BURST 1
add_to_export XMIT_MODE "$XMIT_MODE_START_XMIT"

if [[ "$XMIT_MODE" != "$XMIT_MODE_START_XMIT" ]] \
  && [[ "$XMIT_MODE" != "$XMIT_MODE_QUEUE_XMIT" ]]; then
  usage
  err 2 "XMIT_MODE can only be \"$XMIT_MODE_START_XMIT\" or \"$XMIT_MODE_QUEUE_XMIT\""
fi

if [[ "$XMIT_MODE" == "$XMIT_MODE_QUEUE_XMIT" ]]; then
  if [[ "$CLONE_SKB" != "0" ]]; then
    err 1 "CLONE_SKB not supported for this mode ($XMIT_MODE_QUEUE_XMIT)"
  fi
  if [[ "$BURST" != "1" ]]; then
    err 1  "bursting not supported for this mode ($XMIT_MODE_QUEUE_XMIT)"
  fi
fi

# This is Ethernet packet size - 4
# NIC adds 4 bytes CRC
# datalen = PKT_SIZE - 14 (Eth) - 20 (IPh) - 8 (UDPh) - MPLS (overhead)
#   https://networkengineering.stackexchange.com/a/34191
#   https://github.com/torvalds/linux/blob/v5.9/net/core/pktgen.c#L2793
add_to_export PKT_SIZE 60

add_to_export THREADS 1

# First thread (F_THREAD) reference the zero indexed CPU number
add_to_export F_THREAD 0

add_to_export COUNT 0
add_to_export DELAY 0
add_to_export INTERVAL 0
add_to_export TIMEOUT 0
add_to_export VERBOSE false
add_to_export DEBUG false

function validate_num_params() {
  local re='^[0-9]+$'
  for param in "$@"; do
    if [[ -z "${!param}" ]]; then
      continue
    fi

    if ! [[ ${!param} =~ $re ]] ; then
      err 2 "$param is not a number!"
    elif (( ${!param} < 0 )); then
      err 2 "$param should be greater then 0!"
    fi
  done
}

validate_num_params \
  DST_PORT \
  CLONE_SKB \
  BURST \
  PKT_SIZE \
  THREADS \
  F_THREAD \
  COUNT \
  DELAY \
  INTERVAL \
  TIMEOUT

if (( BURST < 1 )); then
  err 2 "BURST should be no less then 1"
fi
if (( PKT_SIZE < 42 )); then
  err 2 "PKT_SIZE should be not less then 42 (14 + 20 + 8)"
fi

add_to_export L_THREAD "$(( THREADS + F_THREAD - 1 ))"

if [[ -z "${DEST_IP:-}" ]]; then
  if [[ -z "$IP6" ]]; then
    add_to_export DEST_IP "198.18.0.42"
  else
    add_to_export DEST_IP "FD00::1"
  fi
  warn "Missing destination IP address."
fi

if [[ -z "${DST_MAC:-}" ]]; then
  add_to_export DST_MAC "90:e2:ba:ff:ff:ff"
  warn "Missing destination MAC address."
fi

if [[ "$#" -gt 0 ]]; then
  warn "Ignore non-option arguments: $*"
fi

if [[ "$VERBOSE" == true ]]; then
  echo
  (
    printf -- "--------- | -----\\n"
    printf "PARAMETER | VALUE\\n"
    printf -- "--------- | -----\\n"
    for param in "${all_params[@]}"; do
      printf "%s | %s\\n" "$param" "${!param:-\"\"}"
    done
  ) | column -t | sed 's/^/[VERBOSE] /'
fi

if [[ ! -d /proc/net/pktgen ]]; then
  info "Loading kernel module: pktgen"
  modprobe pktgen
fi
