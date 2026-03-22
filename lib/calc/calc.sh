#!/bin/bash

function calc_available_puts() {
  local OPTS=$(getopt -o m:M:d:Wi:r --long min-strike:,max-strike:,spread:,weekly,input:,read-cache -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
  local get_option_quotes=false
  local get_for_weekly_equities=false
  local read_from_cache=false
  while true; do
    case "$1" in
      -m|--min-strike)
        if is_num "$2"; then
          local opt_min_strike="$2"
        fi
        shift 2
        ;;
      -M|--max-strike)
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
      -i|--input)
        local input_file="$2"
        shift 2
        ;;
      -r|--read-cache)
        read_from_cache=true
        shift
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
  elif $read_from_cache; then
    local all_symbols=$(get_all_saved_option_file_symbols)
  else
    local all_symbols=$(get_all_symbols_from_stdin)
  fi

  declare -a price_symbol_pairs
  for symbol in ${all_symbols}; do
    if ! quote_file_exists "${symbol}"; then
      get_quote -w "${symbol}"
    fi
    local option_stock_price=$(get_quote_price -r "${symbol}")
    if [ -n "${option_stock_price}" ] && ! option_file_exists "${symbol}"; then
      get_quote_option -w -s "${option_stock_price}" "${symbol}"
    fi
    if [ -z "${option_stock_price}" ] || ! option_file_exists "${symbol}"; then
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

    local option_file=$(get_option_filename "${quote_symbol}")
    if ! jq -e 'has("OptionChainResponse")' ${option_file} > /dev/null; then
      echo "No option detected for ${quote_symbol}"
      continue
    fi

    if [ $(echo "$stock_price < $min_strike" | bc -l) -eq 1 ]; then
      continue
    fi

    num_strikes=$(jq '.OptionChainResponse.OptionPair | length' ${option_file})
    if ! is_num $num_strikes; then
      echo "Error getting number of strikes for ${quote_symbol}"
      continue
    fi

    for i in $(seq 0 $num_strikes); do
      local strike_price=$(jq --argjson i "$i" '.OptionChainResponse.OptionPair.[$i].Put.strikePrice' ${option_file})

      local one_pct_price="$(echo "scale=3; $strike_price * 0.01" | bc)"

      # strike price increases each iteration, if it's larger than max conditions, quit loop
      if [ $(echo "$strike_price >= $stock_price" | bc -l) -eq 1 ] || \
         [ $(echo "$strike_price > $max_strike" | bc -l) -eq 1 ]; then
        break
      elif [ $(echo "$strike_price < $min_strike" | bc -l) -eq 1 ]; then
        # don't perform calculations if strike price is below minimum
        continue
      fi

      local price_spread="$(echo "$stock_price - $strike_price" | bc)"
      if [ $(echo "$price_spread < $min_spread" | bc -l) -eq 1 ]; then
        # spread decreases each iteration, quit loop if it's less than min condition
        break
      fi

      local put_price=$(jq --argjson i "$i" '.OptionChainResponse.OptionPair.[$i].Put.bid' ${option_file})

      if [ $(echo "$put_price >= $one_pct_price" | bc -l) -eq 1 ]; then
        local put_pct="$(echo "scale=3; $put_price / $strike_price" | bc)"
        printf "%-5s %5.2f %4.2f %4.2f %5.2f\n" \
                 "${quote_symbol}" "$strike_price" "$put_price" "$put_pct" "$price_spread"
        echo "${quote_symbol},${stock_price},${strike_price},${put_price},${put_pct},${price_spread}" \
               >> $output_csv_file
        break;
      fi
    done

  done
}

function usage_calc() {
  subcmd_len=3
  sec_line_indent=$((subcmd_len + 3))
  printf "Usage:\n"
  printf "\tetrade calc {-h --help}\n"
  printf "\tetrade calc [subcommand] [options]\n\n"
  printf "Subcommand:\n"
  printf "\t%-${subcmd_len}s - %s\n" "put" \
           "Calculates the percentage of strike price, based on available Bid, for the given stocks"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "and collects the information for puts available above 1% of the strike. Only provides"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "the strike with maximum spread from the stock's lastPrice value for any given stock."
  printf "\t%${sec_line_indent}s%s\n" " " \
           "By default accepts symbols via stdin, separated by ' ', ',', ';', or newline. Use option"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "-W, -i, or -r to specify by other means"
  printf "\n"
  printf "Options:\n"
  option_title_len=19
  printf "\t%-${option_title_len}s %s\n" "-m --min-strike" \
           "Specifies the minimum strike price to perform calculations on and include in output"
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-M --max-strike" \
           "Specifies the maximum strike price to perform calculations on and include in output"
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-d --spread" \
           "Specifies the minimum 'spread' to perform calculations on and include in output."
  printf "\t%${option_title_len}s %s\n" " " \
           "Spread refers to the difference between the strike price and the stock's lastPrice."
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-W --weekly" \
           "Performs calculation on all equities with weekly options available as specified at"
  printf "\t%${option_title_len}s %s\n" " " \
           "www.cboe.com"
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-i --input" \
           "Accepts the name of a file to use as input specifying the symbols for which to"
  printf "\t%${option_title_len}s %s\n" " " \
           "perform calculations. Symbols can be separated by ' ', ',', ';', or newline"
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-r --read-cache" \
           "Performs calculation on all saved quotes found in cache directory specified by CACHE_DIR"
  printf "\t%${option_title_len}s %s\n" " " \
           "in settings."
  printf "\n"
}

function help_calc() {
  printf "Etrade CLI Calc\n"
  printf "\tPerform calculations based on quotes retrieved from Etrade, generating .csv output. Operates\n"
  printf "\ton quotes saved to the local cache (specified by CACHE_DIR in settings) if available, calls\n"
  printf "\t'quote' operations if not available except with the explicit --read-cache option.\n"
  printf "\n"
  usage_calc
}

function execute_calc() {
  local subcommand=$1
  case "$subcommand" in
    put)
      shift
      calc_available_puts "$@"
      ;;
    -h|--help)
      help_calc
      ;;
    *)
      printf "Unrecognized subcommand '${subcommand}'\n\n" 1>&2
      usage_calc 1>&2
      ;;
  esac
}