#!/usr/bin/env bash
# Common parameter parsing for pktgen scripts

set -euo pipefail

# https://marc.info/?l=linux-netdev&m=145221897804178&w=2
export XMIT_MODE_QUEUE_XMIT="queue_xmit"
export XMIT_MODE_START_XMIT="start_xmit"

usage() {
  cat <<EOF
Usage: $0 -i ethX [OPTIONS]
  -i : (\$DEV)       output interface/device (required)
  -d : (\$DEST_IP)   destination IP. CIDR (e.g. 198.18.0.0/15) is also allowed
  -6 : (\$IP6)       IPv6
  -a : (\$DST_MAC)   destination MAC-addr
  -p : (\$DST_PORT)  destination PORT range (e.g. 433-444) is also allowed (default 9)
  -c : (\$CLONE_SKB) SKB clones send before alloc new SKB (default 0)
  -b : (\$BURST)     HW level bursting of SKBs (>= 1, default 1)
  -m : (\$XMIT_MODE) can be <$XMIT_MODE_START_XMIT|$XMIT_MODE_QUEUE_XMIT> (default $XMIT_MODE_START_XMIT)
  -s : (\$PKT_SIZE)  packet size in bytes (>= 14 + 20 + 8, default 60)
  -t : (\$THREADS)   threads to start (<=$(nproc), default 1)
  -f : (\$F_THREAD)  index of first thread (zero indexed CPU number)
  -n : (\$COUNT)     num messages to send per thread, 0 means indefinitely
  -l : (\$DELAY)     add delay between packets in nanoseconds (default 0)
  -g : (\$INTERVAL)  interval of device summary in seconds (default 0, disabled)
  -e : (\$TIMEOUT)   run with a time limit in seconds, 0 means indefinitely
  -v : (\$VERBOSE)   verbose
  -x : (\$DEBUG)     debug

EOF
}

readonly ERR_INVALID_INPUT_PARAM=1

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
      err $ERR_INVALID_INPUT_PARAM "Invalid option: -$OPTARG"
      ;;
    :  )
      usage
      err $ERR_INVALID_INPUT_PARAM "Option -$OPTARG requires an argument."
      ;;
    *  )
      usage
      exit
  esac
done
shift "$(( OPTIND - 1 ))"

ALL_PARAMS=()
add_to_export() {
  local def_val="${2:-}"
  export "$1"="${!1:-$def_val}"
  ALL_PARAMS+=("$1")
}

add_to_export DEV
if [[ -z "$DEV" ]]; then
  usage
  err $ERR_INVALID_INPUT_PARAM "Please specify output device"
fi

add_to_export IP6
add_to_export DST_PORT 9

# Remove a particular character from a string variable
#   https://unix.stackexchange.com/a/104887
if ! [[ "${DST_PORT//-}" =~ ^[0-9]+$ ]]; then
  err $ERR_INVALID_INPUT_PARAM "Port range can only be numbers"
fi

add_to_export CLONE_SKB 0
add_to_export BURST 1
add_to_export XMIT_MODE "$XMIT_MODE_START_XMIT"

if [[ "$XMIT_MODE" != "$XMIT_MODE_START_XMIT" ]] \
  && [[ "$XMIT_MODE" != "$XMIT_MODE_QUEUE_XMIT" ]]; then
  usage
  err $ERR_INVALID_INPUT_PARAM "XMIT_MODE can only be '$XMIT_MODE_START_XMIT' or '$XMIT_MODE_QUEUE_XMIT'"
fi

if [[ "$XMIT_MODE" == "$XMIT_MODE_QUEUE_XMIT" ]]; then
  if (( CLONE_SKB != 0 )); then
    err $ERR_INVALID_INPUT_PARAM "CLONE_SKB is not supported in this mode ($XMIT_MODE_QUEUE_XMIT)"
  fi
  if (( BURST != 1 )); then
    err $ERR_INVALID_INPUT_PARAM "Bursting is not supported in this mode ($XMIT_MODE_QUEUE_XMIT)"
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

validate_num_params() {
  local param
  for param in "$@"; do
    if [[ -z "${!param}" ]]; then
      continue
    fi

    if ! [[ "${!param}" =~ ^[0-9]+$ ]] ; then
      err $ERR_INVALID_INPUT_PARAM "$param is not a valid number!"
    fi
  done
}

validate_num_params \
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
  err $ERR_INVALID_INPUT_PARAM "BURST should be >= 1"
fi
if (( PKT_SIZE < 42 )); then
  err $ERR_INVALID_INPUT_PARAM "PKT_SIZE should be >= 42 (14 + 20 + 8)"
fi
if (( THREADS > "$(nproc)" )); then
  err $ERR_INVALID_INPUT_PARAM "THREADS should not be greater than the number of CPU cores ($(nproc))"
fi

add_to_export L_THREAD "$(( THREADS + F_THREAD - 1 ))"

if [[ -z "${DEST_IP:-}" ]]; then
  if [[ -z "$IP6" ]]; then
    add_to_export DEST_IP "198.18.0.42"
  else
    add_to_export DEST_IP "FD00::1"
  fi
  warn "Set default destination IP to $DEST_IP"
else
  add_to_export DEST_IP
fi

if [[ -z "${DST_MAC:-}" ]]; then
  add_to_export DST_MAC "90:e2:ba:ff:ff:ff"
  warn "Set defualt destination MAC address to $DST_MAC"
else
  add_to_export DST_MAC
fi

if [[ "$#" -gt 0 ]]; then
  warn "Ignore non-option arguments: $*"
fi

print_all_params() {
  {
    printf -- '--------- | -----\n'
    printf 'PARAMETER | VALUE\n'
    printf -- '--------- | -----\n'

    local param
    for param in "${ALL_PARAMS[@]}"; do
      printf '%s | %s\n' "$param" "${!param:-\"\"}"
    done
  } | column -t | sed 's/^/[VERBOSE] /'
}

if [[ "$VERBOSE" == true ]]; then
  print_all_params
fi

if [[ ! -d /proc/net/pktgen ]]; then
  info "Loading kernel module: pktgen"
  modprobe pktgen
fi
