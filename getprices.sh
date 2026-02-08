#!/bin/bash

symbol_csv_file="$1"

if [ ! -f $symbol_csv_file ]; then
  echo "file doesn't exist: $symbol_csv_file" >$2
  exit 1
fi

all_symbols=$(cat ${symbol_csv_file} | awk -F , '{print $1}')

output_price_file=prices.txt
if [ -f $output_price_file ]; then
  rm $output_price_file
fi

for symbol in ${all_symbols}; do
  symbol=$(echo $symbol | sed 's/"//g');
  expected_file="quotes/${symbol}.json"
  if [ ! -f ${expected_file} ]; then
    echo "${expected_file} not found" >$2
    continue;
  fi

  quote_price=$(jq '.QuoteResponse.QuoteData.[0].Fundamental.lastTrade' ${expected_file})
  if [[ ${quote_price} =~ ^[0-9]*\.?[0-9]+$ ]]; then
    echo "$quote_price $symbol" >> $output_price_file
  else
    echo "couldn't find $symbol price" >$2
  fi

done

sorted_output_file=sortedprices.txt

cat ${output_price_file} | sort -n > ${sorted_output_file}
