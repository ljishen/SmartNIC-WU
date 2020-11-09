#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Common parameter parsing for pktgen scripts

set -euo pipefail

function usage() {
  echo ""
  echo "Usage: $0 [-vx] -i ethX"
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
  echo "  -v : (\$VERBOSE)   verbose"
  echo "  -x : (\$DEBUG)     debug"
  echo "  -6 : (\$IP6)       IPv6"
  echo ""
}

##  --- Parse command line arguments / parameters ---
## echo "Commandline options:"
while getopts "s:i:d:m:p:f:t:c:n:b:vxh6" option; do
  case $option in
    i) # interface
      export DEV=$OPTARG
      info "Output device set to: DEV=$DEV"
      ;;
    s)
      export PKT_SIZE=$OPTARG
      info "Packet size set to: PKT_SIZE=$PKT_SIZE bytes"
      ;;
    d) # destination IP
      export DEST_IP=$OPTARG
      info "Destination IP set to: DEST_IP=$DEST_IP"
      ;;
    m) # MAC
      export DST_MAC=$OPTARG
      info "Destination MAC set to: DST_MAC=$DST_MAC"
      ;;
    p) # PORT
      export DST_PORT=$OPTARG
      info "Destination PORT set to: DST_PORT=$DST_PORT"
      ;;
    f)
      export F_THREAD=$OPTARG
      info "Index of first thread (zero indexed CPU number): $F_THREAD"
      ;;
    t)
      export THREADS=$OPTARG
      info "Number of threads to start: $THREADS"
      ;;
    c)
      export CLONE_SKB=$OPTARG
      info "CLONE_SKB=$CLONE_SKB"
      ;;
    n)
      export COUNT=$OPTARG
      info "COUNT=$COUNT"
      ;;
    b)
      export BURST=$OPTARG
      info "SKB bursting: BURST=$BURST"
      ;;
    v)
      export VERBOSE=yes
      info "Verbose mode: VERBOSE=$VERBOSE"
      ;;
    x)
      export DEBUG=yes
      info "Debug mode: DEBUG=$DEBUG"
      ;;
    6)
      export IP6=6
      info "IP6: IP6=$IP6"
      ;;
    h|?|*)
      usage;
      err 2 "[ERROR] Unknown parameters!!!"
  esac
done
shift $(( OPTIND - 1 ))

if [[ -z "${DEV:-}" ]]; then
  usage
  err 2 "Please specify output device"
fi

if [[ -z "${PKT_SIZE:-}" ]]; then
  # NIC adds 4 bytes CRC
  export PKT_SIZE=60
  info "Default packet size set to: $PKT_SIZE bytes"
fi

export IP6="${IP6:-}"

if [[ -z "${DEST_IP:-}" ]]; then
  if [[ -z "$IP6" ]]; then
    export DEST_IP="198.18.0.42"
  else
    export DEST_IP="FD00::1"
  fi
  warn "Missing destination IP address. Default destination IP set to: $DEST_IP"
fi

if [[ -z "${DST_MAC:-}" ]]; then
  export DST_MAC="90:e2:ba:ff:ff:ff"
  warn "Missing destination MAC address. Default destination MAC set to: $DST_MAC"
fi

export DST_PORT="${DST_PORT:-}"

if [[ -z "${THREADS:-}" ]]; then
  export THREADS=1
fi

if [[ -z "${F_THREAD:-}" ]]; then
  # First thread (F_THREAD) reference the zero indexed CPU number
  export F_THREAD=0
fi

export L_THREAD=$(( THREADS + F_THREAD - 1 ))

if [[ -z "${CLONE_SKB:-}" ]]; then
  export CLONE_SKB=0
  info "Default SKB clones set to: $CLONE_SKB"
fi

if [[ -z "${COUNT:-}" ]]; then
  export COUNT=0
  info "Default num of messages send per thread set to: $COUNT (indefinitely)"
fi

if [[ -z "${BURST:-}" ]]; then
  export BURST=1
  info "Default bursting of SKBs set to: $BURST"
fi

export DEBUG="${DEBUG:-no}"
export VERBOSE="${VERBOSE:-no}"

if [[ ! -d /proc/net/pktgen ]]; then
  info "Loading kernel module: pktgen"
  modprobe pktgen
fi
