#!/bin/bash

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
  OPTS=$(getopt -o fw --long file,write -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
  local read_from_file=false
  local write_to_file=false
  while true; do
    case "$1" in
      -f|--file)
        read_from_file=true
        shift
        ;;
      -w|--write)
        write_to_file=true
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
    write_to_file=false
  fi

  local quote_file=$(get_quote_filename "${quote_symbol}")
  if $read_from_file; then
    if quote_file_exists "${quote_symbol}"; then
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
    local quote_text=$( \
      send_etrade_query "${quote_url}?detailFlag=${detail_flag}" quote_params "${decoded_access_secret}" \
    )
  fi

  if ! jq -e 'has("QuoteResponse")' > /dev/null <<< "${quote_text}"; then
    echo "Failed retrieving price: ${quote_symbol}"
    exit 1
  fi
  if $write_to_file; then
    echo "${quote_text}" > "${quote_file}"
  else
    echo "${quote_text}"
  fi
  return 0
}

function get_quote_price() {
  local quote_text
  if quote_text=$(get_quote "$@" "ignore_write") && [[ "${quote_text}" =~ lastTrade\":([0-9]*\.[0-9]*), ]]; then
    quote_price="${BASH_REMATCH[1]}"
    echo "$quote_price"
    return 0
  else
    echo "Failed retrieving price: ${quote_symbol}"
    return 1
  fi
}

function get_quote_option() {
  OPTS=$(getopt -o s:n:fw --long strike-price:,number-strikes:,file,write -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
  local read_from_file=false
  local write_to_file=false
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
      -f|--file)
        read_from_file=true
        shift
        ;;
      -w|--write)
        write_to_file=true
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

  local no_strikes=${opt_no_strikes:-12}
  if ! is_num "${no_strikes}"; then
    echo "Illegal number of strikes: ${no_strikes}"
    return 1
  fi

  local option_file=$(get_option_filename "${quote_symbol}")
  if $read_from_file; then
    if option_file_exists "${quote_symbol}"; then
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

    local option_text=$( \
      send_etrade_query "${full_option_url}" option_params "${decoded_access_secret}" \
    )
  fi

  if $write_to_file; then
    echo "$option_text" > "${option_file}"
  else
    echo "$option_text"
  fi
}

function get_quote_batch() {
  OPTS=$(getopt -o oWf: --long options,weekly,file: -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
  local get_option_quotes=false
  local get_for_weekly_equities=false
  while true; do
    case "$1" in
      -o|--options)
        get_option_quotes=true
        shift
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

  if $get_for_weekly_equities; then
    local all_symbols=$(get_weekly_options_equity_symbols)
  elif [ -n "${input_file}" ]; then
    local all_symbols=$(get_all_symbols_from_file "${input_file}")
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
      if ! stock_price=$(get_quote_price -f ${symbol}); then
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

function execute_quote() {
  subcommand=$1
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
    clean)
      shift
      if [ -d "${QUOTE_DIR}" ]; then
        find "${QUOTE_DIR}" -name "*.json" -delete
      fi
      ;;
    *)
      get_quote "$@"
      ;;
  esac
}