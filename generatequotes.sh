#!/bin/bash

definitions_file=etrade_defns.sh
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

quote_script="./getquote.sh"

if [ ! -f ${quote_script} ]; then
  echo "${quote_script} not found"
  exit 1
fi

output_dir=quotes

if [ ! -d "${output_dir}" ]; then
  mkdir -p "${output_dir}"
fi

./getauth.sh

for symbol in ${all_symbols}; do
  symbol=$(echo $symbol | sed 's/"//g');

  num_attempts=3
  for i in $(seq 1 ${num_attempts}); do
    if ! ${quote_script} ${symbol} ; then
      echo "'${quote_script} ${symbol}' failed"
    else
      break;
    fi
  done


  expected_opt_file="${output_dir}/${symbol}_opt.json"
  expected_file="${output_dir}/${symbol}.json"
  if [ ! -f ${expected_file} ]; then
    echo "${expected_file} not found"
    continue;
  fi
  if [ ! -f ${expected_opt_file} ]; then
    echo "${expected_opt_file} not found"
    continue;
  fi

done

