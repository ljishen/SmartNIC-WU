#!/usr/bin/env bash

set -euo pipefail

if (( $# != 1 )); then
  cat <<EOF
Usage:    $0 DATAFILE

DATAFILE:
    a datafile summarizes results from all platforms,
    typically ending with '.platforms_summary'.
EOF
  exit
fi

DATAFILE="$1"
if ! [[ -f "$DATAFILE" ]]; then
  echo "[ERROR] DATAFILE does not exist: $DATAFILE" >&2
  exit 1
fi

if [[ "${DATAFILE##*.}" != "platforms_summary" ]]; then
  echo "[ERROR] Unsupport datafile: $DATAFILE" >&2
  exit 1
fi

if ! command -v gawk >/dev/null 2>&1; then
  echo "[ERROR] Please install gawk of version >= 4.0"
  exit 2
fi

vergte() { printf '%s\n%s' "$1" "$2" | sort -rCV; }
if ! vergte "$(gawk 'BEGIN { print PROCINFO["version"] }')" "4.0"; then
  echo "[ERROR] Please update gawk to version >= 4.0"
  exit 2
fi


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
STRESSOR_CLASSES_FILE="$SCRIPT_DIR"/stressor_classes.txt

STRESSOR_TO_CLASSES_STR="$(gawk '
  BEGIN { stressor_to_classes_str = "" }

  /^[[:alnum:]-]+/ {
    if ($1 == "STRESSOR")
      next

    stressor_name = $1
    $1 = ""
    stressor_classes = $0
    gsub(/[[:blank:]]+/, "", stressor_classes)
    stressor_to_classes_str = stressor_to_classes_str" ["stressor_name"]=\""stressor_classes"\""
  }

  END { print stressor_to_classes_str }
' "$STRESSOR_CLASSES_FILE")"

SUMMARY_FILEPATH="$DATAFILE".per_class
cat <<EOF >"$SUMMARY_FILEPATH"
# This file is generated by script $(basename -- "$0")
# for platform results summarized in file $(basename -- "$DATAFILE")
#
# Each value is the accumulated  z-score for all stressors in a given
# stressor class for a particular platform.
#
EOF

gawk -v stressor_to_classes_str="$STRESSOR_TO_CLASSES_STR" '
  BEGIN {
    split(stressor_to_classes_str, stressor_to_classes_arr, " ")
    for (i = 1; i <= length(stressor_to_classes_arr); i++) {
      split(stressor_to_classes_arr[i], sc, "=")
      stressor = sc[1]
      gsub(/\[|\]/, "", stressor)
      classes_str = sc[2]
      gsub(/"/, "", classes_str)
      split(classes_str, classes_arr, "|")

      # Map stressor name to stressor classes
      for (j = 1; j <= length(classes_arr); j++) {
        stressor_to_classes[stressor][classes_arr[j]] = ""
      }
    }
  }

  /^[[:alnum:]_\/-]+\t/ {
    if ($1 == "PLATFORM") {
      for (i = 2; i <= NF; i++) {
        # Map stressor column idx to stressor name
        stressors[i] = $i
      }
      next
    } else {
      platform = $1
      platforms[platform] = ""

      for (i = 2; i <= NF; i++) {
        stressor = stressors[i]

        zscore = $i
        sub(/^[[:digit:].]+\//, "", zscore)
        if (zscore ~ /nan/)
          zscore = 0

        for (class in stressor_to_classes[stressor]) {
          all_classes[class] = ""
          platform_to_class_zscore[platform][class] += zscore
        }
      }
    }
  }

  END {
    printf "# Number of stressor classes: %d\n", length(all_classes)
    printf "# Number of platforms: %d\n\n\n", length(platforms)

    # Print header
    printf "STRESSOR_CLASS"
    for (platform in platforms) {
      printf "\t%s", platform
    }
    printf "\n\n"

    for (class in all_classes) {
      printf class
      for (platform in platforms) {
        printf "\t%.6f", platform_to_class_zscore[platform][class]
      }
      printf "\n"
    }
  }
' "$DATAFILE" >>"$SUMMARY_FILEPATH"

echo "Written summary file to $SUMMARY_FILEPATH"
