#!/bin/bash

function get_options_csv_filename() {
  local type_lower="$1"
  local min_strike="${2:-0}"
  local max_strike="${3:-10000}"
  local date_string=$(date +"%Y"-"%m"-"%d")
  echo "onepct_${type_lower}s${date_string}_${min_strike}-${max_strike}.csv"
}

function parse_calc_opts() {
  local OPTS=$(getopt -o m:M:d:Wi:r --long min-strike:,max-strike:,spread:,weekly,input:,read-cache -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
  unset opt_min_spread
  unset opt_min_strike
  unset opt_max_strike
  unset input_file
  get_option_quotes=false
  get_for_weekly_equities=false
  read_from_cache=false
  while true; do
    case "$1" in
      -m|--min-strike)
        if is_num "$2"; then
          opt_min_strike="$2"
        else
          echo "Invalid value for --min-strike: '$2'" >&2
          return 1
        fi
        shift 2
        ;;
      -M|--max-strike)
        if is_num "$2"; then
          opt_max_strike="$2"
        else
          echo "Invalid value for --max-strike: '$2'" >&2
          return 1
        fi
        shift 2
        ;;
      -d|--spread)
        if is_num "$2"; then
          opt_min_spread="$2"
        else
          echo "Invalid value for --spread: '$2'" >&2
          return 1
        fi
        shift 2
        ;;
      -W|--weekly)
        get_for_weekly_equities=true
        shift
        ;;
      -i|--input)
        input_file="$2"
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

}

function get_price_symbol_pairs() {
  local -n price_symbols="$1"

  if $get_for_weekly_equities; then
    local all_symbols=$(get_weekly_options_equity_symbols)
  elif [ -n "${input_file}" ]; then
    local all_symbols=$(get_all_symbols_from_file "${input_file}")
  elif $read_from_cache; then
    local all_symbols=$(get_all_saved_option_file_symbols)
  else
    local all_symbols=$(get_all_symbols_from_stdin)
  fi

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
    price_symbols+=("${option_stock_price},${symbol}")
  done
}

function calc_available_options() {
  local option_type="$1"
  shift

  if [[ "$option_type" != "Put" && "$option_type" != "Call" ]]; then
    echo "Error: option_type must be 'Put' or 'Call', got '${option_type}'" >&2
    return 1
  fi

  declare -a price_symbol_pairs
  get_price_symbol_pairs price_symbol_pairs

  local readonly min_strike="${opt_min_strike:-0}"
  local readonly max_strike="${opt_max_strike:-10000}"
  local readonly min_spread="${opt_min_spread:-0}"

  local type_lower="${option_type,,}"
  local output_csv_file=$(get_options_csv_filename "${type_lower}" "${min_strike}" "${max_strike}")

  echo "SYMBOL,PRICE,STRIKE,${option_type^^}_BID,PCT,SPREAD" > "${output_csv_file}"

  local pair stock_price quote_symbol
  for pair in "${price_symbol_pairs[@]}"; do
    IFS=',' read stock_price quote_symbol <<< "${pair}"

    local option_file=$(get_option_filename "${quote_symbol}")
    if ! jq -e 'has("OptionChainResponse")' "${option_file}" > /dev/null; then
      echo "No option detected for ${quote_symbol}"
      continue
    fi

    if [[ "$option_type" == "Put" ]]; then
      if [ $(echo "$stock_price < $min_strike" | bc -l) -eq 1 ]; then
        continue
      fi
    else
      if [ $(echo "$stock_price < $min_strike" | bc -l) -eq 1 ] || \
         [ $(echo "$stock_price > $max_strike" | bc -l) -eq 1 ]; then
        continue
      fi
    fi

    local num_strikes=$(jq '.OptionChainResponse.OptionPair | length' "${option_file}")
    if ! is_num "$num_strikes"; then
      echo "Error getting number of strikes for ${quote_symbol}"
      continue
    fi

    local seq_args one_pct_price
    if [[ "$option_type" == "Put" ]]; then
      seq_args="0 $((num_strikes - 1))"
    else
      seq_args="$((num_strikes - 1)) -1 0"
      one_pct_price="$(echo "scale=3; $stock_price * 0.01" | bc)"
    fi

    for i in $(seq $seq_args); do
      local strike_price=$(jq --argjson i "$i" ".OptionChainResponse.OptionPair[$i].${option_type}.strikePrice" "${option_file}")
      local option_bid=$(jq --argjson i "$i" ".OptionChainResponse.OptionPair[$i].${option_type}.bid" "${option_file}")

      if [[ "$strike_price" == "null" || "$option_bid" == "null" ]]; then
        echo "Warning: missing ${option_type} data at index $i for ${quote_symbol}, skipping" >&2
        continue
      fi

      local price_spread pct_basis
      if [[ "$option_type" == "Put" ]]; then
        one_pct_price="$(echo "scale=3; $strike_price * 0.01" | bc)"
        if [ $(echo "$strike_price >= $stock_price" | bc -l) -eq 1 ] || \
           [ $(echo "$strike_price > $max_strike" | bc -l) -eq 1 ]; then
          break
        elif [ $(echo "$strike_price < $min_strike" | bc -l) -eq 1 ]; then
          continue
        fi
        price_spread="$(echo "$stock_price - $strike_price" | bc)"
        pct_basis="$strike_price"
      else
        if [ $(echo "$strike_price <= $stock_price" | bc -l) -eq 1 ]; then
          break
        fi
        price_spread="$(echo "$strike_price - $stock_price" | bc)"
        pct_basis="$stock_price"
      fi

      if [ $(echo "$price_spread < $min_spread" | bc -l) -eq 1 ]; then
        break
      fi

      if [ $(echo "$option_bid >= $one_pct_price" | bc -l) -eq 1 ]; then
        local opt_pct="$(echo "scale=3; $option_bid / $pct_basis" | bc)"
        printf "%-5s %5.2f %4.2f %4.2f %5.2f\n" \
               "${quote_symbol}" "$strike_price" "$option_bid" "$opt_pct" "$price_spread"
        echo "${quote_symbol},${stock_price},${strike_price},${option_bid},${opt_pct},${price_spread}" \
             >> "${output_csv_file}"
        break
      fi
    done
  done
}

function calc_available_puts() {
  parse_calc_opts "$@" && calc_available_options "Put"
}

function calc_available_calls() {
  parse_calc_opts "$@" && calc_available_options "Call"
}

function calc_skew() {
  parse_calc_opts "$@" || return 1

  local min_strike="${opt_min_strike:-0}"
  local max_strike="${opt_max_strike:-10000}"
  local put_csv=$(get_options_csv_filename "puts" "${min_strike}" "${max_strike}")
  local call_csv=$(get_options_csv_filename "calls" "${min_strike}" "${max_strike}")

  calc_available_options "Put" && \
  calc_available_options "Call" && \
  call_and_put_diff "${call_csv}" "${put_csv}"
}

call_and_put_diff() {
  local call_file="$1"
  local put_file="$2"

  if ! [ -f "$call_file" ] || ! [ -f "$put_file" ]; then
    echo "file not found"
    return 1
  fi

  local all_calls=$(cat "$call_file")
  local all_puts=$(cat "$put_file")

  local date_string=$(date +"%Y"-"%m"-"%d")
  local output_csv_file=diff${date_string}.csv

  echo "SYMBOL,Stock Price,Call Spread, Put Spread,Diff" > "${output_csv_file}"

  for call_line in $all_calls; do
    local call_symbol=$(echo "$call_line" | awk -F , '{print $1}')
    if [[ "$call_symbol" == "SYMBOL" ]]; then
      continue
    fi
    local stock_price=$(echo "$call_line" | awk -F , '{print $2}')
    local call_spread=$(echo "$call_line" | awk -F , '{print $6}')
    local put_spread="NA"
    local diff=0
    for put_line in $all_puts; do
      local put_symbol=$(echo "$put_line" | awk -F , '{print $1}')
      if [[ "$call_symbol" != "$put_symbol" ]]; then
        continue
      fi
      put_spread=$(echo "$put_line" | awk -F , '{print $6}')
      local diff="$(echo "$call_spread - $put_spread" | bc -l)"
    done
    echo "$call_symbol,$stock_price,$call_spread,$put_spread,$diff" >> "${output_csv_file}"
  done
}

function usage_calc() {
  subcmd_len=4
  sec_line_indent=$((subcmd_len + 3))
  printf "Usage:\n"
  printf "\tetrade calc {-h --help}\n"
  printf "\tetrade calc [put | call | skew] [options]\n"
  printf "\tetrade calc diff call_csv_filename put_csv_filename\n\n"
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
  printf "\t%-${subcmd_len}s - %s\n" "call" \
           "Calculates the percentage of stock price, based on available Bid per strike, for the given"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "stocks and collects the information for calls available above 1% of the stock."
  printf "\t%${sec_line_indent}s%s\n" " " \
           "Only provides the strike with maximum spread from the stock's lastPrice value for any given stock."
  printf "\t%${sec_line_indent}s%s\n" " " \
           "By default accepts symbols via stdin, separated by ' ', ',', ';', or newline. Use option"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "-W, -i, or -r to specify by other means"
  printf "\t%-${subcmd_len}s - %s\n" "skew" \
           "Runs 'put', 'call', and 'diff' in sequence with the same options, producing all three output"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "files in one command. Accepts the same options as 'put' and 'call'."
  printf "\t%-${subcmd_len}s - %s\n" "diff" \
           "Calculates the difference in spread between call and put given files produced by the 'calc' 'put'"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "and 'call' subcommands."
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
    call)
      shift
      calc_available_calls "$@"
      ;;
    skew)
      shift
      calc_skew "$@"
      ;;
    diff)
      shift
      call_and_put_diff "$@"
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