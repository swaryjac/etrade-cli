#!/bin/bash

definitions_file=etrade_defns.sh
if [ ! -f ${definitions_file} ]; then
  echo "Can't source ${definitions_file}"
  exit 1
fi

source ${definitions_file}

if [ -z ${key_value} ]; then
  echo "keyfile not found: ${key_file}"
  exit 1
fi
if [ -z ${secret_value} ]; then
  echo "secretfile not found: ${secret_file}"
  exit 1
fi

if [[ -z "${access_token}" || -z "${access_secret}" ]]; then
  authorize_script="./getauth.sh"
  if [ ! -f ${authorize_script} ]; then
    echo "no access or secret token, no ${authorize_script} script found"
    exit 1
  fi
  if ! ${authorize_script} ; then
    echo "no access or secret token, ${authorize_script} failed"
    exit 1
  fi
  source ${definitions_file}
  if [[ -z "${access_token}" || -z "${access_secret}" ]]; then
    echo "Failed authorization"
    exit 1
  fi
fi

encoded_access_token="${access_token}"
encoded_access_secret="${access_secret}"

if [[ -z "${encoded_access_token}" || -z "${encoded_access_secret}" ]]; then
  echo "access parsing failed"
  exit 1
fi
decoded_access_secret=$(pctDecode ${encoded_access_secret})

quote_symbol=$1
if [ -z ${quote_symbol} ]; then
  echo "quote symbol not provided"
  exit 1
fi

quote_url="${quote_url_base}${quote_symbol}.json"

detail_flag=FUNDAMENTAL

timestamp=$(date +%s)
nonce=$(date +%s.%N | openssl base64 | sed -e 's/[+=/]//g')

http_method=GET

declare -A quote_params

quote_params["detailFlag"]="${detail_flag}"
quote_params["oauth_consumer_key"]="${key_value}"
quote_params["oauth_nonce"]="${nonce}"
quote_params["oauth_signature_method"]="HMAC-SHA1"
quote_params["oauth_timestamp"]="${timestamp}"
quote_params["oauth_token"]="${encoded_access_token}"

encoded_quote_signature=$( \
  calculate_hmacsha1_signature ${http_method} ${quote_url} quote_params ${secret_value} ${decoded_access_secret} \
)

quote_params["oauth_signature"]="${encoded_quote_signature}"
# detailFlag calculated in signature, but appended to url, not used in header fields
unset "quote_params["detailFlag"]"

quote_file="quotes/${quote_symbol}.json"
if [ -f $quote_file ]; then
  rm $quote_file
fi

http_get "${quote_url}?detailFlag=${detail_flag}" quote_params "${quote_file}"

quote_text=$(cat ${quote_file})

if [[ "${quote_text}" =~ lastTrade\":([0-9]*\.[0-9]*), ]]; then
  quote_price="${BASH_REMATCH[1]}"
else
  echo "failed retrieving price"
  exit 1
fi

opt_year=$(date --date="Next Friday" +"%Y")
opt_month=$(date --date="Next Friday" +"%m")
opt_day=$(date --date="Next Friday" +"%d")

nonce=$(date +%s.%N | openssl base64 | sed -e 's/[+=/]//g')

no_strikes=12

declare -A option_params

option_params["noOfStrikes"]="${no_strikes}"
option_params["oauth_consumer_key"]="${key_value}"
option_params["oauth_nonce"]="${nonce}"
option_params["oauth_signature_method"]="HMAC-SHA1"
option_params["oauth_timestamp"]="${timestamp}"
option_params["oauth_token"]="${encoded_access_token}"
option_params["strikePriceNear"]="${quote_price}"
option_params["symbol"]="${quote_symbol}"
option_params["expiryYear"]="${opt_year}"
option_params["expiryMonth"]="${opt_month}"
option_params["expiryDay"]="${opt_day}"

encoded_option_signature=$( \
  calculate_hmacsha1_signature ${http_method} ${option_url} option_params ${secret_value} ${decoded_access_secret} \
)

option_params["oauth_signature"]="${encoded_option_signature}"
# parameters calculated in signature, but appended to url, not used in header fields
unset "option_params["noOfStrikes"]"
unset "option_params["strikePriceNear"]"
unset "option_params["symbol"]"
unset "option_params["expiryYear"]"
unset "option_params["expiryMonth"]"
unset "option_params["expiryDay"]"

option_file="quotes/${quote_symbol}_opt.json"
if [ -f $option_file ]; then
  rm $option_file
fi

full_option_url="${option_url}?symbol=${quote_symbol}&strikePriceNear=${quote_price}&noOfStrikes=${no_strikes}&expiryYear=${opt_year}&expiryMonth=${opt_month}&expiryDay=${opt_day}"

http_get "${full_option_url}" option_params ${option_file} 

