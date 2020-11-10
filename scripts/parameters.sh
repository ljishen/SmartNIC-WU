#!/usr/bin/env bash
# Common parameter parsing for pktgen scripts

set -euo pipefail

function usage() {
  echo ""
  echo "Usage: $0 [-evx6] -i ethX"
  echo "  -i : (\$DEV)       output interface/device (required)"
  echo "  -s : (\$PKT_SIZE)  packet size"
  echo "  -d : (\$DEST_IP)   destination IP. CIDR (e.g. 198.18.0.0/15) is also allowed"
  echo "  -m : (\$DST_MAC)   destination MAC-addr"
  echo "  -p : (\$DST_PORT)  destination PORT range (e.g. 433-444) is also allowed"
  echo "  -t : (\$THREADS)   threads to start"
  echo "  -f : (\$F_THREAD)  index of first thread (zero indexed CPU number)"
  echo "  -c : (\$CLONE_SKB) SKB clones send before alloc new SKB"
  echo "  -n : (\$COUNT)     num messages to send per thread, 0 means indefinitely"
  echo "  -b : (\$BURST)     HW level bursting of SKBs"
  echo "  -e : (\$INTERVAL)  summary interval, seconds (default 2)"
  echo "  -v : (\$VERBOSE)   verbose"
  echo "  -x : (\$DEBUG)     debug"
  echo "  -6 : (\$IP6)       IPv6"
  echo ""
}

##  --- Parse command line arguments / parameters ---
while getopts ":i:s:d:m:p:t:f:c:n:b:e:vx6" option; do
  # shellcheck disable=SC2034
  case $option in
    i  ) DEV=$OPTARG ;;
    s  ) PKT_SIZE=$OPTARG ;;
    d  ) DEST_IP=$OPTARG ;;
    m  ) DST_MAC=$OPTARG ;;
    p  ) DST_PORT=$OPTARG ;;
    t  ) THREADS=$OPTARG ;;
    f  ) F_THREAD=$OPTARG ;;
    c  ) CLONE_SKB=$OPTARG ;;
    n  ) COUNT=$OPTARG ;;
    b  ) BURST=$OPTARG ;;
    e  ) INTERVAL=$OPTARG ;;
    v  ) VERBOSE=true ;;
    x  ) DEBUG=true ;;
    6  ) IP6=6 ;;
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
shift $(( OPTIND - 1 ))

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

# NIC adds 4 bytes CRC
add_to_export PKT_SIZE 60
add_to_export IP6

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

add_to_export DST_PORT
add_to_export THREADS 1
# First thread (F_THREAD) reference the zero indexed CPU number
add_to_export F_THREAD 0
add_to_export L_THREAD "$(( THREADS + F_THREAD - 1 ))"

add_to_export CLONE_SKB 0
add_to_export COUNT 0
add_to_export BURST 1
add_to_export INTERVAL 2
add_to_export VERBOSE false
add_to_export DEBUG false

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
  echo
fi

if [[ ! -d /proc/net/pktgen ]]; then
  info "Loading kernel module: pktgen"
  modprobe pktgen
fi
