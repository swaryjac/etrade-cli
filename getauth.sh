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

if retrieve_auth_keys; then
  if is_authorization_valid; then
    echo "authorization already good"
    exit 0
  else
    authorization_result=$?
    if [[ ${authorization_result} == 10 ]] && renew_auth_token; then
      echo "renewed authorization"
      exit 0
    else
      clear_auth_keys
    fi
  fi
fi

declare -A request_params

request_params["oauth_callback"]="oob"

request_token_response=$(send_etrade_query "${oauth_request_url}" request_params "")

if [[ "${request_token_response}" =~ oauth_token=(.*)\&oauth_token_secret=(.*)\&oauth_callback_confirmed.* ]]; then
  encoded_request_token="${BASH_REMATCH[1]}"
  encoded_request_secret="${BASH_REMATCH[2]}"
else
  echo "${request_token_response}" > request_response.txt
  echo "response parsing failed, output in request_response.txt"
  exit 1
fi

decoded_request_token=$(pct_decode ${encoded_request_token})
decoded_request_secret=$(pct_decode ${encoded_request_secret})

authorize_url="https://us.etrade.com/e/t/etws/authorize?key=${key_value}&token=${encoded_request_token}"

echo ""
echo "************************************"
if command -v xdg-open &> /dev/null; then
  xdg-open "${authorize_url}" &> /dev/null &
  echo "If browser page didn't load, go to:"
fi
echo "${authorize_url}"
echo "************************************"
echo ""

read -p "Input verification code: " verification_code
if [ -z verification_code ]; then
  echo "no code entered"
  exit 1
fi

declare -A authorize_params

authorize_params["oauth_token"]="${encoded_request_token}"
authorize_params["oauth_verifier"]="${verification_code}"

access_response=$(send_etrade_query "${oauth_access_url}" authorize_params ${decoded_request_secret})

if ! set_auth_keys "${access_response}"; then
  echo "${access_response}" >> access_response.txt
  echo "response parsing failed, output in access_response.txt"
fi

