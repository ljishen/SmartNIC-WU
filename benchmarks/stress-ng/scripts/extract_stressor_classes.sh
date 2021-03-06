#!/usr/bin/env bash

set -euo pipefail

if (( $# != 1 )); then
  cat <<EOF
Usage: $0 <stress-ng_repo_dir>

EOF
  exit
fi

STRESS_NG_REPO_DIR="$1"

if ! [[ -d "$STRESS_NG_REPO_DIR" ]]; then
  echo "[ERROR] Directory does not exist: $STRESS_NG_REPO_DIR" >&2
  exit 1
fi

repo_fetch_url="$(git -C "$STRESS_NG_REPO_DIR" remote get-url origin)"
if ! [[ "$repo_fetch_url" =~ stress-ng/?$ ]]; then
  echo "[ERROR] The directory does not look like a stress-ng repo." >&2
  exit 1
fi

# shellcheck disable=SC2155
declare -a STRESSOR_SRC_FILES="($(awk '
    BEGIN {
      in_src_varaible = 0
      stressor_src_files_str = ""
    }

    !in_src_varaible && /^STRESS_SRC =/ {
      in_src_varaible = 1
      next
    }

    !in_src_varaible { next }

    !/stress-[[:alnum:]_-]+\.c/ {
      print stressor_src_files_str
      exit
    }

    { stressor_src_files_str = stressor_src_files_str" \""$1"\"" }
  ' "$STRESS_NG_REPO_DIR"/Makefile))"

for STRESS_SRC in "${STRESSOR_SRC_FILES[@]}"; do
  # shellcheck disable=SC2155
  declare -A STRESSOR_TO_CLASSES+="($(awk '
    BEGIN {
      in_variable = 0
      stressor_name = ""
      stressor_classes = ""
      stressor_to_classes_str = ""
    }

    !in_variable && /stressor_info_t stress_[[:alnum:]_]+_info = {/ {
      stressor_name = $2
      gsub(/^stress_|_info$/, "", stressor_name)

      # See https://github.com/ColinIanKing/stress-ng/blob/V0.12.02/core-helper.c#L656
      gsub(/_/, "-", stressor_name)

      in_variable = 1
      next
    }

    !in_variable { next }

    /\.stressor = [[:alnum:]_]+,|}/ {
      if (NF != 3 || $3 == "stress_not_implemented,") {
        in_variable = 0
      }
      next
    }

    /\.class = [[:alnum:]_| ]+,/ {
      # How to print field from nth to the last
      #   https://stackoverflow.com/a/2961994
      $1 = $2 = ""
      stressor_classes = $0
      gsub(/^[[:blank:]]+|,$|CLASS_/, "", stressor_classes)

      # Some stressor source files define multiple stress_*_info
      # (e.g., stress-link.c), so we cannot stop processing and
      # exit here.
      stressor_to_classes_str = stressor_to_classes_str" ["stressor_name"]=\""stressor_classes"\""
    }

    END { print stressor_to_classes_str }
  ' "$STRESS_NG_REPO_DIR"/"$STRESS_SRC"))"
done

sort_array() {
  local -n _arr=$1
  local IFS=$'\n'

  # Sort elements in an array
  #   https://stackoverflow.com/a/11789688
  # shellcheck disable=SC2207
  _arr=($(sort <<<"${_arr[*]}"))
}

declare -a STRESSORS=("${!STRESSOR_TO_CLASSES[@]}")
sort_array STRESSORS

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OUTPUT_FILE="$SCRIPT_DIR"/stressor_classes.txt

cat <<EOF >"$OUTPUT_FILE"
# This file is generated by script $(basename -- "$0")
# Please do not modify this file directly.
#
# Number of stressors: ${#STRESSORS[@]}


STRESSOR	CLASSES

EOF

for STRESSOR in "${STRESSORS[@]}"; do
  tabs=$'\t\t'
  if (( ${#STRESSOR} >= 8 )); then
    tabs=$'\t'
  fi
  printf '%s%s%s\n' "$STRESSOR" "$tabs" "${STRESSOR_TO_CLASSES[$STRESSOR]}"
done >>"$OUTPUT_FILE"
echo "Written classes of stressors to $OUTPUT_FILE"
