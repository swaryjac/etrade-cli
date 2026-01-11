#!/bin/bash

option_list_file="options_input.txt"
if [ ! -f $option_list_file ]; then
  echo "file $option_list_file not found"
  exit 1
fi

all_symbols=$(cat ${option_list_file} | awk '{print $2}')

put_index=0
if [[ -n $1 ]]; then
  put_index=$1
fi
echo $put_index

output_file=onepct_options_${put_index}.txt

if [ -f $output_file ]; then
  rm $output_file
fi

for quote_symbol in $all_symbols; do

  option_file="quotes/${quote_symbol}_opt.json"

  if [ ! -f $option_file ]; then
    echo "file $option_file not found"
    continue
  fi

  stock_price=$(jq '.OptionChainResponse.nearPrice' ${option_file})

  one_pct_price="$(echo "scale=3; $stock_price * 0.01" | bc)"
#  echo "10% - $one_pct_price"

  put_price=$(jq --argjson put_index "$put_index" '.OptionChainResponse.OptionPair.[$put_index].Put.bid' ${option_file})
  strike_price=$(jq --argjson put_index "$put_index" '.OptionChainResponse.OptionPair.[$put_index].Put.strikePrice' ${option_file})

#  echo "$put_price $strike_price"
#  echo $quote_symbol $put_price / $stock_price
#  echo "scale=3; $put_price / $stock_price" | bc
#  echo $one_pct_price

  if [ $(echo "$put_price >= $one_pct_price" | bc -l) -eq 1 ]; then
    echo good: "$put_price $strike_price"
    echo "${quote_symbol} ${stock_price} - strike: ${strike_price} bid: ${put_price}" >> $output_file
  fi

#  if [ $(echo "$put_price < $one_pct_price" | bc -l) -eq 1 ]; then
#    echo bad: "$put_price $strike_price"
#    echo "${quote_symbol} ${stock_price} - strike: ${strike_price} bid: ${put_price}"
#  fi
done
