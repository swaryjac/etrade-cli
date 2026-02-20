#!/bin/bash

source "$PARENT_PATH/lib/quote/cache_files.sh"
source "$PARENT_PATH/lib/quote/ticker_symbols.sh"

quote_url_base="https://api.etrade.com/v1/market/quote/"
option_url="https://api.etrade.com/v1/market/optionchains.json"

function import_secret_variables() {
  if ! has_or_get_authorization > /dev/null; then
    echo "Error: No Authorization available"
    return 1
  fi
  if [[ -z "${access_token}" || -z "${access_secret}" ]]; then
    echo "Failed retrieving authorization token/secret"
    return 1
  fi
  export decoded_access_secret=$(pct_decode ${access_secret})
  return 0
}

function get_quote() {
  local OPTS=$(getopt -o rw --long read-cache,write-cache -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
  local read_from_cache=false
  local write_to_cache=false
  while true; do
    case "$1" in
      -r|--read-cache)
        read_from_cache=true
        shift
        ;;
      -w|--write-cache)
        write_to_cache=true
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

  local quote_symbol=$1
  shift
  if ! is_ticker_symbol_valid "$quote_symbol" ; then
    echo "Quote symbol invalid: ${quote_symbol}"
    return 1
  fi
  if [[ $1 == "ignore_write" ]]; then
    write_to_cache=false
  fi

  local quote_file=$(get_quote_filename "${quote_symbol}")
  if $read_from_cache; then
    if ! quote_file_exists "${quote_symbol}"; then
      echo "Couldn't find quote file: ${quote_file}"
      return 1
    fi
    local quote_text=$(cat "${quote_file}")
  else
    if ! import_secret_variables; then
      return 1
    fi

    local quote_url="${quote_url_base}${quote_symbol}.json"

    local detail_flag=FUNDAMENTAL

    declare -A quote_params

    quote_params["detailFlag"]="${detail_flag}"
    quote_params["oauth_token"]="${access_token}"

    echo "Getting ${quote_symbol} quote"

    local quote_text=$( \
      send_etrade_query "${quote_url}?detailFlag=${detail_flag}" quote_params "${decoded_access_secret}" \
        > /dev/null \
    )
  fi

  if ! jq -e 'has("QuoteResponse")' > /dev/null <<< "${quote_text}"; then
    echo "Failed retrieving price: ${quote_symbol}"
    exit 1
  fi
  if $write_to_cache; then
    echo "${quote_text}" > "${quote_file}"
  else
    echo "${quote_text}"
  fi
  return 0
}

function get_quote_price() {
  local quote_text
  if quote_text=$(get_quote "$@" "ignore_write") && [[ "${quote_text}" =~ lastTrade\":([0-9]*\.[0-9]*), ]]; then
    local quote_price="${BASH_REMATCH[1]}"
    echo "$quote_price"
    return 0
  else
    echo "Failed retrieving price: ${quote_symbol}"
    return 1
  fi
}

function get_quote_option() {
  local OPTS=$(getopt -o s:n:rw --long strike-price:,number-strikes:,read-cache,write-cache -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
  local read_from_cache=false
  local write_to_cache=false
  while true; do
    case "$1" in
      -s|--strike-price)
        local opt_strike_price="$2"
        shift 2
        ;;
      -n|--number-strikes)
        local opt_no_strikes="$2"
        shift 2
        ;;
      -r|--read-cache)
        read_from_cache=true
        shift
        ;;
      -w|--write-cache)
        write_to_cache=true
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

  local quote_symbol=$1
  shift
  if ! is_ticker_symbol_valid "$quote_symbol" ; then
    echo "Quote symbol invalid: ${quote_symbol}"
    return 1
  fi

  local strike_price=${opt_strike_price:-$(get_quote_price "${quote_symbol}")}
  if ! is_num "${strike_price}"; then
    echo "Illegal strike price: ${strike_price}"
    return 1
  fi

  local no_strikes=${opt_no_strikes:-20}
  if ! is_num "${no_strikes}"; then
    echo "Illegal number of strikes: ${no_strikes}"
    return 1
  fi

  local option_file=$(get_option_filename "${quote_symbol}")
  if $read_from_cache; then
    if ! option_file_exists "${quote_symbol}"; then
      echo "Couldn't find option file: ${option_file}"
      return 1
    fi
    local option_text=$(cat "${option_file}")
  else

    if ! import_secret_variables; then
      return 1
    fi

    local opt_year=$(date --date="Next Friday" +"%Y")
    local opt_month=$(date --date="Next Friday" +"%m")
    local opt_day=$(date --date="Next Friday" +"%d")

    declare -A option_params

    option_params["noOfStrikes"]="${no_strikes}"
    option_params["oauth_token"]="${access_token}"
    option_params["strikePriceNear"]="${strike_price}"
    option_params["symbol"]="${quote_symbol}"
    option_params["expiryYear"]="${opt_year}"
    option_params["expiryMonth"]="${opt_month}"
    option_params["expiryDay"]="${opt_day}"

    local full_option_url="${option_url}?symbol=${quote_symbol}&strikePriceNear=${strike_price}&noOfStrikes=${no_strikes}&expiryYear=${opt_year}&expiryMonth=${opt_month}&expiryDay=${opt_day}"

    echo "Getting ${quote_symbol} option"

    local option_text=$( \
      send_etrade_query "${full_option_url}" option_params "${decoded_access_secret}" > /dev/null \
    )
  fi

  if $write_to_cache; then
    echo "$option_text" > "${option_file}"
  else
    echo "$option_text"
  fi
}

function get_quote_batch() {
  local OPTS=$(getopt -O oWi: --long options,weekly,input: -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
  local get_option_quotes=false
  local get_for_weekly_equities=false
  while true; do
    case "$1" in
      -O|--options)
        get_option_quotes=true
        shift
        ;;
      -W|--weekly)
        get_for_weekly_equities=true
        shift
        ;;
      -i|--input)
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

  if $get_for_weekly_equities; then
    local all_symbols=$(get_weekly_options_equity_symbols)
  elif [ -n "${input_file}" ]; then
    local all_symbols=$(get_all_symbols_from_cache "${input_file}")
  else
    local all_symbols=$(get_all_symbols_from_stdin)
  fi
  all_symbols=$(echo "${all_symbols}" | sed 's/[,;]/ /g')

  for symbol in ${all_symbols}; do
    if ! is_ticker_symbol_valid "${symbol}"; then
      echo "Illegal symbol: ${symbol}"
      continue
    fi

    local readonly num_attempts=3
    for i in $(seq 1 ${num_attempts}); do
      if ! get_quote -w ${symbol}; then
        echo "Attempt $i Quote for '${symbol}' failed"
      else
        break;
      fi
    done

    if $get_option_quotes; then
      if ! stock_price=$(get_quote_price -r ${symbol}); then
        echo "Failed getting price: ${symbol}"
        continue
      fi
      for i in $(seq 1 ${num_attempts}); do
        if ! get_quote_option -w -s "${stock_price}" ${symbol}; then
          echo "Attempt $i Option for '${symbol}' failed"
        else
          break;
        fi
      done
    fi
  done
}

function usage_quote() {
  subcmd_len=6
  sec_line_indent=$((subcmd_len + 3))
  printf "Usage:\n"
  printf "\tetrade quote {-h --help}\n"
  printf "\tetrade quote [subcommand] [options] <ticker_symbol>\n\n"
  printf "Subcommand:\n"
  printf "\t%-${subcmd_len}s - %s\n" "[none]" \
           "Prints a FUNDAMENTAL json quote for the stock of the given ticker symbol"
  printf "\n"
  printf "\t%-${subcmd_len}s - %s\n" "price" \
           "Prints the 'last price' for the stock of the given ticker symbol"
  printf "\n"
  printf "\t%-${subcmd_len}s - %s\n" "option" \
           "Prints json quote of an option chain for the stock of the given ticker symbol."
  printf "\t%${sec_line_indent}s%s\n" " " \
           "Automatically uses expiration date of 'next friday' as provided by the 'date' cmd."
  printf "\n"
  printf "\t%-${subcmd_len}s - %s\n" "batch" \
           "Gets quotes for a set of stocks, optionally also getting option chains"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "Saves quotes to the cache directory specified by CACHE_DIR in settings"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "By default accepts symbols via stdin, separated by ' ', ',', ';', or newline"
  printf "\n"
  printf "\t%-${subcmd_len}s - %s\n" "clear" \
           "Deletes all quotes in the cache directory specified by CACHE_DIR in settings"
  printf "\n"
  printf "Options:\n"
  option_title_len=19
  printf "\t%-${option_title_len}s %s\n" "-w --write-cache" \
           "Saves output to file in the cache directory specified by CACHE_DIR in settings"
  printf "\t%${option_title_len}s %s\n" " " "Does not print quote to stdout"
  printf "\t%${option_title_len}s %s\n" " " "Valid for: [none], option"
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-r --read-cache" \
           "Reads requested information from file in cache directory specified by CACHE_DIR in"
  printf "\t%${option_title_len}s %s\n" " " \
           "settings. If supplied with -w option, -r takes precedence"
  printf "\t%${option_title_len}s Valid for: [none], price, option\n" " "
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-s --strike-price" \
           "The price retrieve options quote 'near'. Defaults to the stock's lastPrice."
  printf "\t%${option_title_len}s Valid for: option when not reading from local cache\n" " "
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-n --number-strikes" \
           "The number of strikes, centered around the strike-price, to retrieve a quote for"
  printf "\t%${option_title_len}s Valid for: option when not reading from local cache\n" " "
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-O --options" \
           "Saves an option chain quote in addition to FUNDAMENTAL stock quote"
  printf "\t%${option_title_len}s Valid for: batch\n" " "
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-W --weekly" \
           "Instead of accepting symbols via stdin, uses all equities with weekly options"
  printf "\t%${option_title_len}s %s\n" " " \
           "available as specified at www.cboe.com"
  printf "\t%${option_title_len}s Valid for: batch\n" " "
  printf "\n"
  printf "\t%-${option_title_len}s %s\n" "-i --input" \
           "Accepts the name of a file to use as input specifying the symbols for which to"
  printf "\t%${option_title_len}s %s\n" " " \
           "retrieve quotes. Symbols can be separated by ' ', ',', ';', or newline"
  printf "\t%${option_title_len}s Valid for: batch\n" " "
}

function help_quote() {
  printf "Etrade CLI Quote\n"
  printf "\tGets stock and option quotes using Etrade's api. Individual quotes are printed to stdout\n"
  printf "\tby default. Batch operations and optionally individual quotes are saved to file in a\n"
  printf "\tlocal cache directory specified by CACHE_DIR in settings. The quotessaved to cache are\n"
  printf "\tused by 'calc' operations.  Individual quote retrievals can also display quotes from the\n"
  printf "\tcache instead of accessing Etrade.\n"
  printf "\tThe 'auth' operations will be called if necessary by the 'quote' operations.\n"
  printf "\n"
  usage_quote
}

function execute_quote() {
  local subcommand=$1
  case "$subcommand" in
    price)
      shift
      get_quote_price "$@"
      ;;
    option)
      shift
      get_quote_option "$@"
      ;;
    batch)
      shift
      get_quote_batch "$@"
      ;;
    clear)
      shift
      if [ -d "${CACHE_DIR}" ]; then
        find "${CACHE_DIR}" -name "*.json" -delete
      fi
      ;;
    -h|--help)
      help_quote
      ;;
    "")
      printf "Error: Ticker Symbol required\n\n" 2>&1
      usage_quote 2>&1
      ;;
    -*)
      get_quote "$@"
      ;;
    *)
      if ! is_ticker_symbol_valid "${!#}"; then
        printf "Error: unrecognized subcommand '%s' or illegal ticker symbol '%s'\n\n" \
               "$subcommand" "${!#}" 2>&1
        usage_quote 2>&1
        return 1
      fi
      get_quote "$@"
      ;;
  esac
}