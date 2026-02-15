#!/bin/bash

definitions_file=lib/common/http_defns.sh
if [ ! -f ${definitions_file} ]; then
  echo "Can't source ${definitions_file}"
  exit 1
fi

source ${definitions_file}

date_string=$(date +"%Y"-"%m"-"%d")
all_weekly_file="weekly${date_string}.csv"
symbol_csv_file="weekly_equities${date_string}.csv"

if [ ! -f $all_weekly_file ]; then
  weekly_csv_url="https://www.cboe.com/available_weeklys/get_csv_download/"

  declare -A empty_array=()
  http_get ${weekly_csv_url} empty_array ${all_weekly_file}
fi

equities_header_regex="^Available.*Equity$"
sed -n '/'"${equities_header_regex}"'/,$p' ${all_weekly_file} | sed '1d' > ${symbol_csv_file}

if [ ! -f $symbol_csv_file ]; then
  echo "file doesn't exist: $symbol_csv_file"
  exit 1
fi

all_symbols=$(cat ${symbol_csv_file} | awk -F , '{print $1}')

output_dir=quotes

if [ ! -d "${output_dir}" ]; then
  mkdir -p "${output_dir}"
fi


for symbol in ${all_symbols}; do
  symbol=$(echo $symbol | sed 's/"//g');

  num_attempts=3
  for i in $(seq 1 ${num_attempts}); do
    if ! quote_text=$(./etrade quote -w ${symbol}); then
      echo "Quote for '${symbol}' failed"
    else
      break;
    fi
  done

  if ! stock_price=$(./etrade quote price -f ${symbol}); then
    echo "Failed reading price: ${symbol}"
    continue
  fi

  for i in $(seq 1 ${num_attempts}); do
    if ! option_text=$(./etrade quote option -w ${symbol}); then
      echo "Option for '${symbol}' failed"
    else
      break;
    fi
  done

done

