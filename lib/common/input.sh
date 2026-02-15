#!/bin/bash

function get_weekly_options_equity_symbols() {
  local readonly date_string=$(date +"%Y"-"%m"-"%d")
  local readonly all_weekly_file="/dev/shm/.weekly${date_string}.csv"

  if [ ! -f $all_weekly_file ]; then
    local readonly weekly_csv_url="https://www.cboe.com/available_weeklys/get_csv_download/"
    declare -A empty_array=()
    if ! http_get ${weekly_csv_url} empty_array ${all_weekly_file}; then
      echo "Error getting weekly options from ${weekly_csv_url}"
      return 1
    fi
  fi

  local readonly equities_header_regex="^Available.*Equity$"
  sed -n '/'"${equities_header_regex}"'/,$p' ${all_weekly_file} \
    | sed '1d' \
    | awk -F , '{print $1}' \
    | sed 's/"//g'
}

function get_all_symbols_from_file() {
  local input_file="$1"

  if [ ! -f "${input_file}" ]; then
    echo "Error ${input_file} not found" >&2
    return 1
  fi
  local all_symbols=$(cat "${input_file}")
  echo "${all_symbols}" | sed 's/[,;]/ /g'
  return 0
}

function get_all_symbols_from_stdin() {
  if [[ -t 0 ]]; then
    echo "Enter stock symbols, separated by ',' ';' ' ' or newlines. Ctrl+d to complete:" > /dev/tty
  fi
  local all_symbols=""
  while IFS= read -r line; do
    all_symbols="$all_symbols $line"
  done
  echo "${all_symbols}" | sed 's/[,;]/ /g'
  return 0
}
