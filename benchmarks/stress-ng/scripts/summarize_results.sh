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
  local -r dirname="$(dirname "$filepath")"
  local -r platform="${dirname/#$BENCHMARK_RESULT_DIR}"
  local -r filename="$(basename "$filepath")"
  # !! we use the dot as the field separator in the filename
  local -ir profile_idx="${filename##*.}"
  local -r jobname="${filename%%.*}"
  local profile_name="$platform"____"$jobname"____"$profile_idx"
  profile_name="${profile_name//[^[:alnum:]_]/_}"

  if (( profile_idx == 1 )); then
    HEAD_PROFILE_NAME_TO_SUMMARY_FILEPATH["$profile_name"]="${filepath/%.*/.summary}"
  fi

  declare -g -A "$profile_name"
  declare -n stressor_to_bogo=$profile_name

  echo "Reading file $filepath ..."

  local stressor bogo_ops_per_second
  # loop over the results from grep
  #   https://stackoverflow.com/a/16318005
  # loop without losing the last entry
  #   https://stackoverflow.com/a/5010679
  while read -r -d '#' group || [[ -n "$group" ]]; do
    stressor="$(
      grep --perl-regexp --only-matching \
        'stressor: \K[\w-]+' <<< "$group"
    )"
    bogo_ops_per_second="$(
      grep --perl-regexp --only-matching \
        'bogo-ops-per-second-real-time: \K[\d.]+' <<< "$group"
    )"

    # shellcheck disable=SC2034
    stressor_to_bogo["$stressor"]=$bogo_ops_per_second
  done < <(
    grep "bogo-ops-per-second-real-time: " \
      --before-context=3 --group-separator='#' "$filepath"
  )
}

print_summary() {
  local head_profile_name
  for head_profile_name in "${!HEAD_PROFILE_NAME_TO_SUMMARY_FILEPATH[@]}"; do
    # shellcheck disable=SC2178
    declare -n stressor_to_bogo=$head_profile_name
    local -a all_stressors=("${!stressor_to_bogo[@]}")

    local -i profile_idx
    for (( profile_idx = 2; ; profile_idx++ )); do
      local profile_name="${head_profile_name/%____[[:digit:]]*/____$profile_idx}"
      # shellcheck disable=SC2178
      declare -n stressor_to_bogo=$profile_name
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

    # sort elements in an array
    #   https://stackoverflow.com/a/11789688
    # shellcheck disable=SC2207
    IFS=$'\n' all_stressors=($(sort <<<"${all_stressors[*]}"))
    unset IFS

    local summary_filepath="${HEAD_PROFILE_NAME_TO_SUMMARY_FILEPATH[$head_profile_name]}"
    local yaml_filepath="${summary_filepath/%.*/.yaml.*}"
    printf '# This file summarizes stress-ng benchmark results for YAML files %s\n\n\n' \
      "${yaml_filepath/#$BENCHMARK_RESULT_DIR}" >"$summary_filepath"

    local -i max_profile_idx="$(( profile_idx - 1 ))"
    # print header
    printf 'STRESSOR\t%s\tAVG\tSTD\n\n' "$(seq -s $'\t' 1 $max_profile_idx)" \
      >>"$summary_filepath"

    local bogo_ops_per_second
    for stressor in "${all_stressors[@]}"; do
      printf '%s\t' "$stressor"
      local -a bogo_ops_ps_cur_stressor=()
      for (( profile_idx = 1; profile_idx <= max_profile_idx; profile_idx++ )); do
        local profile_name="${head_profile_name/%____[[:digit:]]*/____$profile_idx}"
        declare -n stressor_to_bogo=$profile_name
        if [[ -v "stressor_to_bogo[$stressor]" ]]; then
          bogo_ops_per_second="${stressor_to_bogo[$stressor]}"
          if [[ "$bogo_ops_per_second" != "0.000000" ]]; then
            bogo_ops_ps_cur_stressor+=("$bogo_ops_per_second")
          fi
        else
          bogo_ops_per_second="n/a"
        fi
        printf '%s\t' "$bogo_ops_per_second"
      done

      printf '%s\n' "${bogo_ops_ps_cur_stressor[@]}" | awk '
        {
          sum += $0
          sum_sq += $0 ^ 2
        }
        END {
          printf("%.6f\t%.6f\n",
            sum / NR,
            sqrt(sum_sq / NR - (sum / NR) ^ 2))
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
