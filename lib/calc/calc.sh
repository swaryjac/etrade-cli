#!/bin/bash

function calc_available_puts() {
  OPTS=$(getopt -o m:M:d:Wf: --long min_strike:,max_strike:,spread:,weekly,file: -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
  local get_option_quotes=false
  local get_for_weekly_equities=false
  while true; do
    case "$1" in
      -m|--min_strike)
        if is_num "$2"; then
          local opt_min_strike="$2"
        fi
        shift 2
        ;;
      -M|--max_strike)
        if is_num "$2"; then
          local opt_max_strike="$2"
        fi
        shift 2
        ;;
      -d|--spread)
        if is_num "$2"; then
          local opt_min_spread="$2"
        fi
        shift 2
        ;;
      -W|--weekly)
        get_for_weekly_equities=true
        shift
        ;;
      -f|--file)
        local input_file="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        echo "Option Parsing Error"
        return 1
        ;;
    esac
  done

  local readonly min_strike="${opt_min_strike:-0}"
  local readonly max_strike="${opt_max_strike:-10000}"
  local readonly min_spread="${opt_min_spread:-0}"

  if $get_for_weekly_equities; then
    local all_symbols=$(get_weekly_options_equity_symbols)
  elif [ -n "${input_file}" ]; then
    local all_symbols=$(get_all_symbols_from_file "${input_file}")
  else
    local all_symbols=$(get_all_saved_option_file_symbols)
  fi

  declare -a price_symbol_pairs
  for symbol in ${all_symbols}; do
    if ! quote_file_exists "${symbol}"; then
      get_quote -w "${symbol}"
    fi
    local option_stock_price=$(get_quote_price -f "${symbol}")
    if [ -n "${option_stock_price}" ] && ! option_file_exists "${symbol}"; then
      get_quote_option -w -s "${option_stock_price}" "${symbol}"
    fi
    if [ -z ${option_stock_price} ] || ! option_file_exists "${symbol}"; then
      echo "Failed to get option for ${symbol}"
      continue
    fi
    price_symbol_pairs+=("${option_stock_price},${symbol}")
  done

  local date_string=$(date +"%Y"-"%m"-"%d")
  local output_csv_file=onepct_options${date_string}_${min_strike}-${max_strike}.csv

  echo "SYMBOL,PRICE,STRIKE,PUT_BID,PCT,SPREAD" > ${output_csv_file}

  local pair stock_price quote_symbol
  for pair in "${price_symbol_pairs[@]}"; do
    IFS=',' read stock_price quote_symbol <<< "${pair}"
    
    local option_file="quotes/${quote_symbol}_opt.json"
    if ! jq -e 'has("OptionChainResponse")' ${option_file} > /dev/null; then
      echo "No option detected for ${quote_symbol}"
      continue
    fi

    local one_pct_price="$(echo "scale=3; $stock_price * 0.01" | bc)"

    for i in {0..9}; do
      local put_price=$(jq --argjson i "$i" '.OptionChainResponse.OptionPair.[$i].Put.bid' ${option_file})
      local strike_price=$(jq --argjson i "$i" '.OptionChainResponse.OptionPair.[$i].Put.strikePrice' ${option_file})

      if [ $(echo "$strike_price >= $stock_price" | bc -l) -eq 1 ]; then
        break;
      fi

      local price_spread="$(echo "$stock_price - $strike_price" | bc)"
      if [ $(echo "$strike_price > $max_strike" | bc -l) -eq 1 ] || \
         [ $(echo "$strike_price < $min_strike" | bc -l) -eq 1 ] || \
         [ $(echo "$price_spread < $min_spread" | bc -l) -eq 1 ]; then
        continue
      fi

      if [ $(echo "$put_price >= $one_pct_price" | bc -l) -eq 1 ]; then
        local put_pct="$(echo "scale=3; $put_price / $stock_price" | bc)"
        echo "$quote_symbol: $strike_price $put_price $put_pct $price_spread"
        echo "${quote_symbol},${stock_price},${strike_price},${put_price},${put_pct},${price_spread}" >> $output_csv_file
        break;
      fi
    done

  done
}

function execute_calc() {
  subcommand=$1
  case "$subcommand" in
    put)
      shift
      calc_available_puts "$@"
      ;;
    *)
      get_quote "$@"
      ;;
  esac
}