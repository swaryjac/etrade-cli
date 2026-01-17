#!/bin/bash

option_list_file="$1"
if [ ! -f $option_list_file ]; then
  echo "file $option_list_file not found"
  exit 1
fi

all_symbols=$(cat ${option_list_file} | awk '{print $2}')

date_string=$(date +"%Y"-"%m"-"%d")
output_file=onepct_options${date_string}.txt
output_csv_file=onepct_options${date_string}.csv

if [ -f $output_file ]; then
  rm $output_file
fi

echo "SYMBOL,PRICE,STRIKE,PUT_BID,PCT,SPREAD" > ${output_csv_file}

for quote_symbol in $all_symbols; do

  option_file="quotes/${quote_symbol}_opt.json"

  if [ ! -f $option_file ]; then
    echo "file $option_file not found"
    continue
  fi

  stock_price=$(jq '.OptionChainResponse.nearPrice' ${option_file})

  one_pct_price="$(echo "scale=3; $stock_price * 0.01" | bc)"
#  echo "10% - $one_pct_price"

  put_price=$(jq '.OptionChainResponse.OptionPair.[0].Put.bid' ${option_file})
  strike_price=$(jq '.OptionChainResponse.OptionPair.[0].Put.strikePrice' ${option_file})

  for i in {1..5}; do
    if [ $(echo "$strike_price >= $stock_price" | bc -l) -eq 1 ]; then
      break;
    fi

#    echo "$put_price $strike_price"
#    echo $quote_symbol $put_price / $stock_price
#    echo "scale=3; $put_price / $stock_price" | bc
#    echo $one_pct_price

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
