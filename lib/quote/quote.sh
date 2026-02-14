#!/bin/bash

quote_url_base="https://api.etrade.com/v1/market/quote/"
option_url="https://api.etrade.com/v1/market/optionchains.json"

function set_secret_values() {
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

function is_symbol_valid() {
  if [ -n $1 ] && [[ "$1" =~ [A-Z]{1,5} ]]; then
    return 0
  fi
  return 1
}

function get_quote() {
  if ! set_secret_values; then
    return 1
  fi

  local quote_symbol=$1
  shift
  if ! is_symbol_valid "$quote_symbol" ; then
    echo "Quote symbol invalid: ${quote_symbol}"
    exit 1
  fi

  local quote_url="${quote_url_base}${quote_symbol}.json"

  local detail_flag=FUNDAMENTAL

  declare -A quote_params

  quote_params["detailFlag"]="${detail_flag}"
  quote_params["oauth_token"]="${access_token}"
  local quote_text=$( \
    send_etrade_query "${quote_url}?detailFlag=${detail_flag}" quote_params "${decoded_access_secret}" \
  )

  if ! jq -e 'has("QuoteResponse")' > /dev/null <<< "${quote_text}"; then
    echo "Failed retrieving price: ${quote_symbol}"
    exit 1
  fi
  echo "${quote_text}"
  exit 0
}

function get_quote_price() {
  local quote_text
  if quote_text=$(get_quote "$@") && [[ "${quote_text}" =~ lastTrade\":([0-9]*\.[0-9]*), ]]; then
    quote_price="${BASH_REMATCH[1]}"
    echo "$quote_price"
    return 0
  else
    echo "Failed retrieving price: ${quote_symbol}"
    return 1
  fi
}

function get_quote_option() {
  if ! set_secret_values; then
    return 1
  fi

  OPTS=$(getopt -o s:n: --long strike-price:,number-strikes: -- "$@")
  if [[ $? != 0 ]]; then
    echo "Bad options"
    return 1
  fi
  eval set -- "$OPTS"
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
  if ! is_symbol_valid "$quote_symbol" ; then
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
  echo "$option_text"
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
    *)
      get_quote "$@"
      ;;
  esac
}