#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
BENCHMARK_RESULT_DIR="$(readlink --canonicalize "$SCRIPT_DIR"/../../../results/stress-ng)/"

printf 'Working on result directory: %s\n\n' "$BENCHMARK_RESULT_DIR"

if ! [[ -d "$BENCHMARK_RESULT_DIR" ]]; then
  echo "Result directory does not exist!" >&2
  exit 1
fi


declare -A JOBNAME_TO_PLATFORMS=()

get_profile_name() {
  local -r jobname="$1" platform="$2"
  local profile_name="$jobname"____"$platform"
  profile_name="${profile_name//[^[:alnum:]_]/_}"
  echo "$profile_name"
}

process_file() {
  local -r filepath="$1"
  local -r dirname="$(dirname -- "$filepath")"
  local -r platform="${dirname/#$BENCHMARK_RESULT_DIR}"
  local -r filename="$(basename -- "$filepath")"
  # !! we use the dot as the field separator in the filename
  local -r jobname="${filename%%.*}"
  local profile_name="$(get_profile_name "$jobname" "$platform")"

  JOBNAME_TO_PLATFORMS["$jobname"]+=" '$platform'"

  declare -g -A "$profile_name"
  declare -n stressor_to_bogo=$profile_name

  echo "Reading file $filepath ..."

  # shellcheck disable=SC2034
  stressor_to_bogo=("$(
    awk '
      BEGIN {
        mean_field = 0
        stressor_to_bogo_str = ""
      }

      !/^[:blank:]*#*/ {
        if (mean_field == 0) {
          for (i = 1; i <= NF; i++) {
            if ($i == "MEAN") {
              mean_field = i
              next
            }
          }
        } else if ($mean_field ~ /^[0-9.]+$/) {
          stressor_to_bogo = stressor_to_bogo" ["$1"]="$mean_field
        }
      }

      END {
        print stressor_to_bogo
      }
    ' "$filepath"
  )")
}

sort_array() {
  local -n _arr=$1

  # sort elements in an array
  #   https://stackoverflow.com/a/11789688
  # shellcheck disable=SC2207
  IFS=$'\n' _arr=($(sort <<<"${_arr[*]}"))
  unset IFS
}

print_summary() {
  local jobname
  for jobname in "${!JOBNAME_TO_PLATFORMS[@]}"; do
    local -a platforms=("${JOBNAME_TO_PLATFORMS[$jobname]}")
    sort_array platforms

    local platform profile_name
    local -a all_stressors=()
    for platform in "${platforms[@]}"; do
      profile_name="$(get_profile_name "$jobname" "$platform")"

      # shellcheck disable=SC2178
      declare -n stressor_to_bogo=$profile_name

      if (( ${#all_stressors[@]} == 0 )); then
        all_stressors=("${!stressor_to_bogo[@]}")
      else
        local stressor
        for stressor in "${!stressor_to_bogo[@]}"; do
          # check if an element in an array
          #   https://stackoverflow.com/a/15394738
          # shellcheck disable=SC2076,SC2199
          if ! [[ " ${all_stressors[@]} " =~ " $stressor " ]]; then
            all_stressors+=("$stressor")
            echo "[WARN] added stressor '$stressor' from $profile_name"
          fi
        done
      fi
    done

    # shellcheck disable=SC2207
    IFS=$'\n' all_stressors=($(sort <<<"${all_stressors[*]}")) && unset IFS

    local summary_filepath="$BENCHMARK_RESULT_DIR"/"$jobname".platforms_summary
    
    printf 'PLATFORM\t%s' "" >> "$summary_filepath"
  done
}


while IFS= read -r -d '' line; do
  process_file "$(readlink --canonicalize "$line")"
done < <(
  find "$BENCHMARK_RESULT_DIR" -type f -name '*.summary' -print0
)
echo

print_summary
echo

echo 'Done!'
