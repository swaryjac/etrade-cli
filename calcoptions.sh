#!/bin/bash

function is_num() {
  if [[ "$1" =~ ^[0-9]+(\.[0-9]*)?$ ]]; then
    return 0
  fi
  return 1
}

option_list_file="$1"
if [ ! -f $option_list_file ]; then
  echo "file $option_list_file not found"
  exit 1
fi

if [[ $# > 1 ]] && is_num "$2"; then
  min_price="$2"
else
  min_price=0
fi
if [[ $# > 2 ]] && is_num "$3"; then
  max_price="$3"
else
  max_price=10000
fi

all_symbols=$( \
  sort -n "${option_list_file}" \
  | awk -v min="$min_price" -v max="$max_price" \
      '$1 >= min && $1 <= max {print $1 "," $2}' \
)

date_string=$(date +"%Y"-"%m"-"%d")
output_file=onepct_options${date_string}.txt
output_csv_file=onepct_options${date_string}_${min_price}-${max_price}.csv

if [ -f $output_file ]; then
  rm $output_file
fi

echo "SYMBOL,PRICE,STRIKE,PUT_BID,PCT,SPREAD" > ${output_csv_file}

for quote_line in $all_symbols; do
  IFS=',' read stock_price quote_symbol <<< "${quote_line}"

  option_file="quotes/${quote_symbol}_opt.json"

  if [ ! -f $option_file ]; then
    echo "file $option_file not found"
    continue
  fi
  if ! jq -e 'has("OptionChainResponse")' ${option_file} > /dev/null; then
    echo "No option detected for ${quote_symbol}"
    continue
  fi

  one_pct_price="$(echo "scale=3; $stock_price * 0.01" | bc)"

  put_price=$(jq '.OptionChainResponse.OptionPair.[0].Put.bid' ${option_file})
  strike_price=$(jq '.OptionChainResponse.OptionPair.[0].Put.strikePrice' ${option_file})

  for i in {1..5}; do
    if [ $(echo "$strike_price >= $stock_price" | bc -l) -eq 1 ]; then
      break;
    fi

    if [ $(echo "$put_price >= $one_pct_price" | bc -l) -eq 1 ]; then
      put_pct="$(echo "scale=3; $put_price / $stock_price" | bc)"
      price_spread="$(echo "$stock_price - $strike_price" | bc)"
      echo good: "$put_price $strike_price $put_pct"
      echo "${quote_symbol} ${stock_price} - strike: ${strike_price} bid: ${put_price} pct: ${put_pct} spread: ${price_spread}" >> $output_file
      echo "${quote_symbol},${stock_price},${strike_price},${put_price},${put_pct},${price_spread}" >> $output_csv_file
      break;
    fi

    put_price=$(jq --argjson i "$i" '.OptionChainResponse.OptionPair.[$i].Put.bid' ${option_file})
    strike_price=$(jq --argjson i "$i" '.OptionChainResponse.OptionPair.[$i].Put.strikePrice' ${option_file})
  done
done
