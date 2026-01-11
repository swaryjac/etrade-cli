#!/bin/bash

symbol_csv_file="$1"

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

for symbol in ${all_symbols}; do
  symbol=$(echo $symbol | sed 's/"//g');

  if ! ${quote_script} ${symbol} ; then
    echo "'${quote_script} ${symbol}' failed"
    exit 1
  fi


  expected_file="${output_dir}/${symbol}.json"
  if [ ! -f ${expected_file} ]; then
    echo "${expected_file} not found"
    continue;
  fi

done

