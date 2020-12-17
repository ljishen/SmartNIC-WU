#!/usr/bin/env bash
# Common functions used by pktgen scripts
#  - Depending on bash 4.2 (or higher) syntax

set -euo pipefail

# https://stackoverflow.com/a/51548669
shopt -s expand_aliases
alias trace_on='{ if [[ "${DEBUG:-false}" == true ]]; then echo; set -x; fi } 2>/dev/null'
alias trace_off='{ set +x; } 2>/dev/null'
export PS4='# ${BASH_SOURCE:-"$0"}:${LINENO} - ${FUNCNAME[0]:+${FUNCNAME[0]}()} > '

# stop "^C" being printed when Ctrl-C
#   https://unix.stackexchange.com/a/333804
stty -echoctl

## -- General shell logging cmds --
err() {
  local -ir exit_status="$1"
  shift
  printf "\\033[1;31m[ERROR] %s\\033[0m\\n" "$*" >&2
  exit "$exit_status"
}

warn() {
  echo "[WARN] $*" >&2
}

info() {
  if [[ "${VERBOSE:-false}" == true ]]; then
    echo "[INFO] $*"
  fi
}

readonly ERR_INVALID_PARAM_FORMAT=2
readonly ERR_INVALID_PERMISSION=3
readonly ERR_PROGRAM=4


## -- Pktgen proc config commands -- ##
export PROC_DIR=/proc/net/pktgen
#
# Three different shell functions for configuring the different
# components of pktgen:
#   pg_ctrl(), pg_thread() and pg_set().
#
# These functions correspond to pktgens different components.
# * pg_ctrl()   control "pgctrl" (/proc/net/pktgen/pgctrl)
# * pg_thread() control the kernel threads and binding to devices
# * pg_set()    control setup of individual devices
pg_ctrl() {
  local proc_file="pgctrl"
  proc_cmd "$proc_file" "$@"
}

pg_thread() {
  local -i thread=$1
  shift

  if (( thread > $(nproc) )); then
    err $ERR_PROGRAM "Thread number ($thread) is greater than the number of CPU cores ($(nproc))"
  fi

  local proc_file="kpktgend_$thread"
  proc_cmd "$proc_file" "$@"
}

pg_set() {
  local dev=$1
  local proc_file="$dev"
  shift
  proc_cmd "$proc_file" "$@"
}

proc_cmd() {
  local proc_file=$1
  local -i exit_status=0
  # after shift, the remaining args are contained in $@
  shift

  local proc_ctrl="$PROC_DIR/$proc_file"
  if [[ ! -e "$proc_ctrl" ]]; then
    err $ERR_PROGRAM "proc file: $proc_ctrl does not exists"
  elif [[ ! -w "$proc_ctrl" ]]; then
    err $ERR_INVALID_PERMISSION "proc file: $proc_ctrl not writable"
  fi

  # Quoting of "$@" is important for space expansion
  trace_on
  echo "$@" | tee "$proc_ctrl" >/dev/null 2>&1 || exit_status=$?
  trace_off

  local result=''
  if [[ "$proc_file" != "pgctrl" ]]; then
    result=$(grep "Result:" "$proc_ctrl")
  fi

  if (( exit_status )); then
    err $ERR_PROGRAM "Write error ($exit_status) occurred cmd: echo $* > $proc_ctrl"$'\n\t'"$result"
  fi
}

export EXIT_TRAP_FUNCS=()

on_exit() {
  local -i exit_status="$?"
  trace_off

  # Once we received this signal, we can ignore the following ones
  # so that we can finish the remaining cleanning up process.
  trap '' INT

  if ! [[ -d "$PROC_DIR" ]]; then
    return
  fi
  PS4='\033[0D[ON_EXIT] '

  pg_ctrl "stop"

  # run customized trap functions
  local func
  for func in "${EXIT_TRAP_FUNCS[@]}"; do
    $func
  done

  pg_ctrl "reset"

  if (( exit_status == 130 )); then
    # Exit with 0 if the program is self-terminated
    exit 0
  fi
}
[[ $EUID -eq 0 ]] && trap on_exit EXIT

check_root_privileges() {
  if [[ "$EUID" -ne 0 ]]; then
    err $ERR_INVALID_PERMISSION "This program should be run as root"
  fi
}

# Exact input device's NUMA node info
get_iface_node() {
  local node
  node=$(</sys/class/net/"$1"/device/numa_node)
  if (( node == -1 )); then
    echo 0
  else
    echo "$node"
  fi
}

# Given an Dev/iface, get its queues' irq numbers
get_iface_irqs() {
  local IFACE=$1
  local queues="${IFACE}-.*TxRx"

  local irqs
  irqs=$(grep "$queues" /proc/interrupts | cut -f1 -d:)
  [[ -z "$irqs" ]] && irqs=$(grep "$IFACE" /proc/interrupts | cut -f1 -d:)
  [[ -z "$irqs" ]] && irqs=$(for i in $(ls -Ux /sys/class/net/"$IFACE"/device/msi_irqs) ;\
    do grep "$i:.*TxRx" /proc/interrupts | grep -v fdir | cut -f 1 -d : ;\
    done)
  [[ -z "$irqs" ]] && err $ERR_PROGRAM "Could not find interrupts for $IFACE"

  echo "$irqs"
}

# Given a NUMA node, return cpu ids belonging to it.
get_node_cpus() {
  local node=$1
  local node_cpu_list node_cpu_range_list
  node_cpu_range_list=$(cut -f1- -d, --output-delimiter=" " \
    /sys/devices/system/node/node"$node"/cpulist)

  for cpu_range in $node_cpu_range_list
  do
    node_cpu_list="$node_cpu_list "$(seq -s " " "${cpu_range//-/ }")
  done

  echo "$node_cpu_list"
}

# Check $1 is in between $2, $3 ($2 <= $1 <= $3)
in_between() { [[ ($1 -ge $2) && ($1 -le $3) ]] ; }

# Extend shrunken IPv6 address.
# fe80::42:bcff:fe84:e10a => fe80:0:0:0:42:bcff:fe84:e10a
extend_addr6() {
  local addr=$1
  local sep=: sep2=:: sep_cnt
  sep_cnt=$(tr -cd $sep <<< "$1" | wc -c)
  local shrink

    # separator count should be (2 <= $sep_cnt <= 7)
    if ! (in_between "$sep_cnt" 2 7); then
      err $ERR_INVALID_PARAM_FORMAT "Invalid IP6 address: $1"
    fi

    # if shrink '::' occurs multiple, it's malformed.
    shrink=( $(egrep -o "$sep{2,}" <<< "$addr") )
    if [[ ${#shrink[@]} -ne 0 ]]; then
      if [[ ${#shrink[@]} -gt 1 || ( ${shrink[0]} != "$sep2" ) ]]; then
        err $ERR_INVALID_PARAM_FORMAT "Invalid IP6 address: $1"
      fi
    fi

    # add 0 at begin & end, and extend addr by adding :0
    [[ ${addr:0:1} == "$sep" ]] && addr=0${addr}
    [[ ${addr: -1} == "$sep" ]] && addr=${addr}0
    echo "${addr/$sep2/$(printf ':0%.s' $(seq $(( 8 - sep_cnt )))):}"
}

# Given a single IP(v4/v6) address, whether it is valid.
validate_addr() {
  # check function is called with (funcname)6
  [[ ${FUNCNAME[1]: -1} == 6 ]] && local IP6=6
  local bitlen=$(( IP6 ? 128 : 32 ))
  local len=$(( IP6 ? 8 : 4 ))
  local max=$(( 2**(len*2)-1 ))
  local net prefix
  local addr sep

  IFS='/' read -r net prefix <<< "$1"
  [[ $IP6 ]] && net=$(extend_addr6 "$net")

  # if prefix exists, check (0 <= $prefix <= $bitlen)
  if [[ -n $prefix ]]; then
    if ! (in_between "$prefix" 0 $bitlen); then
      err $ERR_INVALID_PARAM_FORMAT "Invalid prefix: /$prefix"
    fi
  fi

  # set separator for each IP(v4/v6)
  [[ $IP6 ]] && sep=: || sep=.
  IFS=$sep read -ra addr <<< "$net"

  # array length
  if [[ ${#addr[@]} -ne "$len" ]]; then
    err $ERR_INVALID_PARAM_FORMAT "Invalid IP$IP6 address: $1"
  fi

  # check each digit (0 <= $digit <= $max)
  local digit
  for digit in "${addr[@]}"; do
    [[ $IP6 ]] && digit=$(( 16#$digit ))
    if ! (in_between $digit 0 $max); then
      err $ERR_INVALID_PARAM_FORMAT "Invalid IP$IP6 address: $1"
    fi
  done

  return 0
}

validate_addr6() { validate_addr "$@" ; }

# Given a single IP(v4/v6) or CIDR, return minimum and maximum IP addr.
parse_addr() {
  # check function is called with (funcname)6
  [[ ${FUNCNAME[1]: -1} == 6 ]] && local IP6=6
  local net prefix
  local min_ip max_ip

  IFS='/' read -r net prefix <<< "$1"
  [[ $IP6 ]] && net=$(extend_addr6 "$net")

 if [[ -z "$prefix" ]]; then
    min_ip=$net
    max_ip=$net
  else
    # defining array for converting Decimal 2 Binary
    # 00000000 00000001 00000010 00000011 00000100 ...
    local d2b='{0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1}'
    [[ $IP6 ]] && d2b+=$d2b
    eval "local D2B=($d2b)"

    local bitlen=$(( IP6 ? 128 : 32 ))
    local remain=$(( bitlen-prefix ))
    local octet=$(( IP6 ? 16 : 8 ))
    local min_mask max_mask
    local min max
    local ip_bit
    local ip sep

    # set separator for each IP(v4/v6)
    [[ $IP6 ]] && sep=: || sep=.
    IFS=$sep read -ra ip <<< "$net"

    min_mask="$(printf '1%.s' $(seq "$prefix"))$(printf '0%.s' $(seq $remain))"
    max_mask="$(printf '0%.s' $(seq "$prefix"))$(printf '1%.s' $(seq $remain))"

    # calculate min/max ip with &,| operator
    local i idx digit
    for i in "${!ip[@]}"; do
      digit=$(( IP6 ? 16#${ip[$i]} : ${ip[$i]} ))
      ip_bit=${D2B[$digit]}

      idx=$(( octet*i ))
      min[$i]=$(( 2#$ip_bit & 2#${min_mask:$idx:$octet} ))
      max[$i]=$(( 2#$ip_bit | 2#${max_mask:$idx:$octet} ))
      [[ $IP6 ]] && { min[$i]=$(printf '%X' ${min[$i]});
                      max[$i]=$(printf '%X' ${max[$i]}); }
    done

    min_ip=$(IFS=$sep; echo "${min[*]}")
    max_ip=$(IFS=$sep; echo "${max[*]}")
  fi

  echo "$min_ip" "$max_ip"
}

parse_addr6() { parse_addr "$@" ; }

# Given a single or range of port(s), return minimum and maximum port number.
parse_ports() {
  local port_str=$1
  local port_list
  local -i min_port
  local -i max_port

  IFS="-" read -ra port_list <<< "$port_str"

  min_port=${port_list[0]}
  max_port=${port_list[1]:-$min_port}

  echo "$min_port" "$max_port"
}

# Given a minimum and maximum port, verify port number.
validate_ports() {
  local -i min_port=$1
  local -i max_port=$2

  # 1 <= port <= 65535
  if (in_between "$min_port" 1 65535); then
    if (in_between "$max_port" 1 65535); then
      if (( min_port <= max_port )); then
        return 0
      fi
    fi
  fi

  err $ERR_INVALID_PARAM_FORMAT "Invalid port(s): $min_port-$max_port"
}
