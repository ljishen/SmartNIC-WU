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
  local profile_name
  profile_name="$(get_profile_name "$jobname" "$platform")"

  JOBNAME_TO_PLATFORMS["$jobname"]+=" '$platform'"

  echo "Reading file $filepath ..."

  # shellcheck disable=SC2140
  declare -g -A "$profile_name"="($(
    awk -F $'\t' '
      BEGIN {
        mean_field = 0
        stressor_to_bogo_str = ""
      }

      /^[[:alnum:]]+/ {
        if (mean_field == 0) {
          for (i = 1; i <= NF; i++) {
            if ($i == "MEAN") {
              mean_field = i
              next
            }
          }
          next
        } else {
          stressor_to_bogo_str = stressor_to_bogo_str" ["$1"]="$mean_field
        }
      }

      END { print stressor_to_bogo_str }
    ' "$filepath"
  ))"
}

sort_array() {
  local -n _arr=$1
  local IFS=$'\n'

  # sort elements in an array
  #   https://stackoverflow.com/a/11789688
  # shellcheck disable=SC2207
  _arr=($(sort <<<"${_arr[*]}"))
}

calculate_zscore() {
  # shellcheck disable=SC2178
  local -n _arr=$1

  awk -v bogo_ops_ps_cur_stressor_str="${_arr[*]}" '
    function is_valid_num(bogo_ops_ps) {
      # bogo_ops_ps can be "nan" or "0.000000"
      return bogo_ops_ps ~ /^[0-9.]+$/ && bogo_ops_ps != "0.000000"
    }

    BEGIN {
      split(bogo_ops_ps_cur_stressor_str, bogo_ops_ps_cur_stressor, " ")

      num_val = 0
      sum = 0
      sq_sum = 0
      for (idx = 1; idx <= length(bogo_ops_ps_cur_stressor); idx++) {
        bogo_ops_ps = bogo_ops_ps_cur_stressor[idx]
        if (is_valid_num(bogo_ops_ps)) {
          num_val++
          sum += bogo_ops_ps
          sq_sum += bogo_ops_ps ^ 2
        }
      }

      mean = sum / num_val
      stdev = sqrt((sq_sum - num_val * mean ^ 2) / (num_val - 1))

      bogo_ops_ps_with_zscore = ""
      for (idx = 1; idx <= length(bogo_ops_ps_cur_stressor); idx++) {
        bogo_ops_ps = bogo_ops_ps_cur_stressor[idx]
        if (is_valid_num(bogo_ops_ps)) {
          zscore = (bogo_ops_ps - mean) / stdev
        } else {
          zscore = "nan"
        }
        bogo_ops_ps_with_zscore = bogo_ops_ps_with_zscore" "bogo_ops_ps"/"zscore
      }

      print bogo_ops_ps_with_zscore
    }
  '
}

print_summary() {
  local jobname
  for jobname in "${!JOBNAME_TO_PLATFORMS[@]}"; do
    local -a platforms="(${JOBNAME_TO_PLATFORMS[$jobname]})"
    sort_array platforms

    local platform profile_name stressor
    local -a all_stressors=()
    for platform in "${platforms[@]}"; do
      profile_name="$(get_profile_name "$jobname" "$platform")"

      # shellcheck disable=SC2178
      local -n stressor_to_bogo=$profile_name

      if (( ${#all_stressors[@]} == 0 )); then
        all_stressors=("${!stressor_to_bogo[@]}")
      else
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
    sort_array all_stressors
    echo

    local summary_filepath="${BENCHMARK_RESULT_DIR}${jobname}".platforms_summary
    echo "Writing summary to $summary_filepath"

    cat <<EOF >"$summary_filepath"
# This file summarizes  stress-ng benchmark results of all platforms
# under the directory of this file.
#
# The value of each stressor is in the format of B/S, where B is the
# average  bogo-ops-per-second-real-time  of  multiple  tests on the
# the same platform,  and S is the  z-score of the value in tests of
# all platforms with respect to the same stressor.
#
# Number of stressors: ${#all_stressors[@]}
# Number of platforms: ${#platforms[@]}


EOF

    # print header
    # shellcheck disable=SC2116
    printf 'PLATFORM\t%s\n\n' "$(IFS=$'\t' && echo "${all_stressors[*]}")" \
      >>"$summary_filepath"

    for stressor in "${all_stressors[@]}"; do
      local -a bogo_ops_ps_cur_stressor=()
      for platform in "${platforms[@]}"; do
        profile_name="$(get_profile_name "$jobname" "$platform")"
        # shellcheck disable=SC2178
        local -n stressor_to_bogo=$profile_name

        if [[ -v "stressor_to_bogo[$stressor]" ]]; then
          bogo_ops_ps_cur_stressor+=("${stressor_to_bogo[$stressor]}")
        else
          bogo_ops_ps_cur_stressor+=("nan")
        fi
      done

      local -a bogo_ops_ps_with_zscore
      IFS=' ' read -r -a bogo_ops_ps_with_zscore \
        <<< "$(calculate_zscore bogo_ops_ps_cur_stressor)"

      # update the stressor_to_bogo array for the
      # current stressor by adding zscores
      local -i platform_idx
      for (( platform_idx = 0;
        platform_idx < ${#platforms[@]};
        platform_idx++ )); do
        platform="${platforms[$platform_idx]}"
        profile_name="$(get_profile_name "$jobname" "$platform")"
        # shellcheck disable=SC2178
        local -n stressor_to_bogo=$profile_name
        stressor_to_bogo["$stressor"]="${bogo_ops_ps_with_zscore[$platform_idx]}"
      done
    done

    # print summary
    {
      for platform in "${platforms[@]}"; do
        printf '%s\t' "$platform"

        profile_name="$(get_profile_name "$jobname" "$platform")"
        # shellcheck disable=SC2178
        local -n stressor_to_bogo=$profile_name

        local -i stressor_idx
        for (( stressor_idx = 0; stressor_idx < ${#all_stressors[@]}; stressor_idx++ )); do
          stressor="${all_stressors[$stressor_idx]}"
          if (( stressor_idx < ${#all_stressors[@]} - 1 )); then
            printf '%s\t' "${stressor_to_bogo[$stressor]}"
          else
            printf '%s\n' "${stressor_to_bogo[$stressor]}"
          fi
        done
      done
    } >>"$summary_filepath"
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
