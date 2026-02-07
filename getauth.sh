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
  echo error
  exit 1
fi

request_params["oauth_signature"]="${encoded_request_signature}"

#token_file="request_token.txt"
#if [ -f $token_file ]; then
#  rm $token_file
#fi

request_token_response=$(http_get "${oauth_request_url}" request_params)

#token_response=$(cat ${token_file})

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

authorize_params["oauth_signature"]="${encoded_authorize_oauth_signature}"

#access_token_file="access_token.txt"
#if [ -f $access_token_file ]; then
#  rm $access_token_file
#fi

access_response=$(http_get "${oauth_access_url}" authorize_params)

#access_response=$(cat ${access_token_file})

if ! set_access_keys "${access_response}"; then
  echo "${access_response}" >> access_response.txt
  echo "response parsing failed, output in access_response.txt"
fi

#if [[ "${access_response}" =~ oauth_token=(.*)\&oauth_token_secret=(.*)$ ]]; then
#  encoded_access_token="${BASH_REMATCH[1]}"
#  encoded_access_secret="${BASH_REMATCH[2]}"
#  echo "token: ${encoded_access_token}, secret: ${encoded_access_secret}"
#else
#  echo "response parsing failed"
#  exit 1
#fi

