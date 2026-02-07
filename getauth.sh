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
  echo "no access or secret token"
fi

http_method=GET

timestamp=$(date +%s)
nonce=$(date +%s%T | openssl base64 | sed -e 's/[+=/]//g')

declare -A request_params

request_params["oauth_callback"]="oob"
request_params["oauth_consumer_key"]="${key_value}"
request_params["oauth_nonce"]="${nonce}"
request_params["oauth_signature_method"]="HMAC-SHA1"
request_params["oauth_timestamp"]="${timestamp}"

encoded_request_signature=$( \
  calculate_hmacsha1_signature ${http_method} ${oauth_request_url} request_params ${secret_value} "" \
)

if [ ! $? -eq 0 ]; then
  echo Error calculating HMAC-SHA1 Signature for Token Request
  exit 1
fi

request_params["oauth_signature"]="${encoded_request_signature}"

request_token_response=$(http_get "${oauth_request_url}" request_params)

if [[ "${request_token_response}" =~ oauth_token=(.*)\&oauth_token_secret=(.*)\&oauth_callback_confirmed.* ]]; then
  encoded_request_token="${BASH_REMATCH[1]}"
  encoded_request_secret="${BASH_REMATCH[2]}"
else
  echo "${request_token_response}" >> request_response.txt
  echo "response parsing failed, output in request_response.txt"
  exit 1
fi

decoded_request_token=$(pctDecode ${encoded_request_token})
decoded_request_secret=$(pctDecode ${encoded_request_secret})

authorize_url="https://us.etrade.com/e/t/etws/authorize?key=${key_value}&token=${encoded_request_token}"

if command -v xdg-open &> /dev/null; then
  xdg-open "${authorize_url}" &
  echo "If browser page didn't load, go to:"
fi
echo "${authorize_url}\n"

read -p "Input verification code: " verification_code
if [ -z verification_code ]; then
  echo "no code entered"
  exit 1
fi

declare -A authorize_params

authorize_params["oauth_consumer_key"]="${key_value}"
authorize_params["oauth_nonce"]="${nonce}"
authorize_params["oauth_signature_method"]="HMAC-SHA1"
authorize_params["oauth_timestamp"]="${timestamp}"
authorize_params["oauth_token"]="${encoded_request_token}"
authorize_params["oauth_verifier"]="${verification_code}"

encoded_authorize_oauth_signature=$( \
  calculate_hmacsha1_signature ${http_method} ${oauth_access_url} authorize_params ${secret_value} ${decoded_request_secret} \
)

if [ ! $? -eq 0 ]; then
  echo Error calculating HMAC-SHA1 Signature for Authorization Request
  exit 1
fi

authorize_params["oauth_signature"]="${encoded_authorize_oauth_signature}"

access_response=$(http_get "${oauth_access_url}" authorize_params)

if ! set_access_keys "${access_response}"; then
  echo "${access_response}" >> access_response.txt
  echo "response parsing failed, output in access_response.txt"
fi

