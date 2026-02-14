#!/bin/bash

quote_url_base="https://api.etrade.com/v1/market/quote/"

function get_quote_price() {

  if ! has_or_get_authorization > /dev/null; then
    echo "Error: No Authorization available"
    exit 1
  fi

  local encoded_access_token="${access_token}"
  local encoded_access_secret="${access_secret}"

  if [[ -z "${encoded_access_token}" || -z "${encoded_access_secret}" ]]; then
    echo "Failed retrieving authorization token/secret"
    exit 1
  fi
  decoded_access_secret=$(pct_decode ${encoded_access_secret})

  quote_symbol=$1
  if [ -z ${quote_symbol} ]; then
    echo "Quote symbol not provided"
    exit 1
  fi

  quote_url="${quote_url_base}${quote_symbol}.json"

  detail_flag=FUNDAMENTAL

  declare -A quote_params

  quote_params["detailFlag"]="${detail_flag}"
  quote_params["oauth_token"]="${encoded_access_token}"
  quote_text=$( \
    send_etrade_query "${quote_url}?detailFlag=${detail_flag}" quote_params "${decoded_access_secret}" \
  )

  if [[ "${quote_text}" =~ lastTrade\":([0-9]*\.[0-9]*), ]]; then
    quote_price="${BASH_REMATCH[1]}"
  else
    echo "Failed retrieving price: ${quote_symbol}"
    exit 1
  fi
}

function execute_quote() {
  subcommand=$1
  case "$subcommand" in
    price)
      shift
      get_quote_price $@
      ;;
    # option)
    #   ;;
    *)
      echo "Bad subcommand"
      return 1
      ;;
  esac
}