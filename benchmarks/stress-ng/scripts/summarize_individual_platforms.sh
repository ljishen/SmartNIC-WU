#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
BENCHMARK_RESULT_DIR="$(readlink --canonicalize "$SCRIPT_DIR"/../../../results/stress-ng)/"

printf 'Working on result directory: %s\n\n' "$BENCHMARK_RESULT_DIR"

if ! [[ -d "$BENCHMARK_RESULT_DIR" ]]; then
  echo "Result directory does not exist!" >&2
  exit 1
fi


declare -A HEAD_PROFILE_NAME_TO_SUMMARY_FILEPATH

process_file() {
  local -r filepath="$1"
  local -r dirname="$(dirname -- "$filepath")"
  local -r platform="${dirname/#$BENCHMARK_RESULT_DIR}"
  local -r filename="$(basename -- "$filepath")"
  # !! we use the dot as the field separator in the filename
  local -ir profile_idx="${filename##*.}"
  local -r jobname="${filename%%.*}"
  local profile_name="$platform"____"$jobname"____"$profile_idx"
  profile_name="${profile_name//[^[:alnum:]_]/_}"

  if (( profile_idx == 1 )); then
    HEAD_PROFILE_NAME_TO_SUMMARY_FILEPATH["$profile_name"]="${filepath/%.*/.summary}"
  fi

  echo "Reading file $filepath ..."

  # shellcheck disable=SC2140
  declare -g -A "$profile_name"="($(
    awk '
      BEGIN {
        in_metrics = 0
        stressor = ""
        bogo_ops_per_second = ""
        stressor_to_bogo_str = ""
      }

      $0 == "metrics:" {
        in_metrics = 1
        next
      }

      !in_metrics { next }

      /^[[:alnum:]]+/ { exit }

      $2 == "stressor:" {
        stressor = $3
        next
      }

      $1 == "bogo-ops-per-second-real-time:" {
        bogo_ops_per_second = $2
        stressor_to_bogo_str = stressor_to_bogo_str" ["stressor"]="bogo_ops_per_second
      }

      END { print stressor_to_bogo_str }
    ' "$filepath"
  ))"
}

get_profile_name() {
  local -r head_profile_name="$1"
  local -ir profile_idx="$2"
  echo "${head_profile_name/%____[[:digit:]]*/____$profile_idx}"
}

sort_array() {
  local -n _arr=$1
  local IFS=$'\n'

  # sort elements in an array
  #   https://stackoverflow.com/a/11789688
  # shellcheck disable=SC2207
  _arr=($(sort <<<"${_arr[*]}"))
}

print_summary() {
  local head_profile_name profile_name
  for head_profile_name in "${!HEAD_PROFILE_NAME_TO_SUMMARY_FILEPATH[@]}"; do
    # shellcheck disable=SC2178
    local -n stressor_to_bogo=$head_profile_name
    local -a all_stressors=("${!stressor_to_bogo[@]}")

    local -i profile_idx
    for (( profile_idx = 2; ; profile_idx++ )); do
      profile_name="$(get_profile_name "$head_profile_name" "$profile_idx")"

      # shellcheck disable=SC2178
      local -n stressor_to_bogo=$profile_name
      if ! [[ -v stressor_to_bogo[@] ]]; then
        # the associative array does not exist
        #   https://stackoverflow.com/a/26931860
        break
      fi

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
    done
    sort_array all_stressors

    local summary_filepath="${HEAD_PROFILE_NAME_TO_SUMMARY_FILEPATH[$head_profile_name]}"
    local yaml_filepath="${summary_filepath/%.*/.yaml.*}"
    local -i max_profile_idx="$(( profile_idx - 1 ))"
    cat <<EOF >"$summary_filepath"
# This file summarizes stress-ng benchmark results for YAML files:
# ${yaml_filepath/#$BENCHMARK_RESULT_DIR}
#
# The values under the indexed columns  (1..n)  are in the format of
# R/S. For column i,  R is the  bogo-ops-per-second-real-time of the
# corresponding stressor in the 'i th' test, and S is the z-score of
# the value in n tests.
#
# Number of tests: $max_profile_idx


EOF

    # print header
    printf 'STRESSOR\t%s\tMEAN\tSTDEV\n\n' \
      "$(seq --format='"%g (raw/z-score)"' --separator=$'\t' 1 $max_profile_idx)" \
      >>"$summary_filepath"

    local bogo_ops_per_second
    for stressor in "${all_stressors[@]}"; do
      printf '%s\t' "$stressor"
      local -a bogo_ops_ps_cur_stressor=()
      for (( profile_idx = 1; profile_idx <= max_profile_idx; profile_idx++ )); do
        profile_name="$(get_profile_name "$head_profile_name" "$profile_idx")"
        local -n stressor_to_bogo=$profile_name
        if [[ -v "stressor_to_bogo[$stressor]" ]]; then
          bogo_ops_per_second="${stressor_to_bogo[$stressor]}"
        else
          bogo_ops_per_second="nan"
        fi
        bogo_ops_ps_cur_stressor+=("$bogo_ops_per_second")
      done

      awk -v bogo_ops_ps_cur_stressor_str="${bogo_ops_ps_cur_stressor[*]}" '
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

          for (idx = 1; idx <= length(bogo_ops_ps_cur_stressor); idx++) {
            bogo_ops_ps = bogo_ops_ps_cur_stressor[idx]
            if (is_valid_num(bogo_ops_ps)) {
              zscore = (bogo_ops_ps - mean) / stdev
              printf("%.6f/%.6f\t", bogo_ops_ps, zscore)
            } else {
              printf("%s/%s\t", bogo_ops_ps, "nan")
            }
          }

          printf("%.6f\t%.6f\n", mean, stdev)
        }
      '
    done >>"$summary_filepath"

    echo "Written summary to $summary_filepath"
  done
}


while IFS= read -r -d '' line; do
  process_file "$(readlink --canonicalize "$line")"
done < <(
  find "$BENCHMARK_RESULT_DIR" -type f -name '*.yaml.*[[:digit:]]' -print0
)
echo

print_summary
echo

echo 'Done!'
