#!/bin/bash

oauth_request_url="https://api.etrade.com/oauth/request_token"
oauth_access_url="https://api.etrade.com/oauth/access_token"

quote_url_base="https://api.etrade.com/v1/market/quote/"
option_url="https://api.etrade.com/v1/market/optionchains.json"

key_file="api_key.txt"
secret_file="api_secret.txt"

if [ -f ${key_file} ]; then
  key_value=$(cat ${key_file})
else
  unset key_value
fi
if [ -f ${secret_file} ]; then
  secret_value=$(cat ${secret_file})
else
  unset secret_value
fi

if access_token_id=$(keyctl request user etrade_api_token 2>/dev/null); then
  access_token=$(keyctl pipe "${access_token_id}")
else
  unset access_token
fi
unset access_token_id

if access_secret_id=$(keyctl request user etrade_api_secret 2>/dev/null); then
  access_secret=$(keyctl pipe "${access_secret_id}")
else
  unset access_secret
fi
unset access_secret_id

function pctEncode() {
  local length="${#1}"
  for ((n = 0; n < length; n++)); do
    local c="${1:n:1}"
    case $c in
      [a-zA-Z0-9.~_-]) printf "$c" ;;
                    *) printf '%%%02X' "'$c"
    esac
  done
}

function pctDecode() {
  local strg="${*}"
  printf '%s' "${strg%%[%+]*}"
  local j="${strg#"${strg%%[%+]*}"}"
  strg="${j#?}"
  case "${j}" in "%"* )
    printf '%b' "\\0$(printf '%o' "0x${strg%"${strg#??}"}")"
 	strg="${strg#??}"
    ;; "+"* ) printf ' '
    ;;    * ) return
  esac
  if [ -n "${strg}" ] ; then pctDecode "${strg}"; fi
}

function set_key() {
  local key_name="$1"
  local key_value="$2"
  echo $key_name $key_value
  if ! keyctl add user "${key_name}" "${key_value}" @u &> /dev/null; then
    local key_id
    if key_id=$(keyctl request user "${key_name}" 2&>1); then
      keyctl update "${key_id}" "${key_value}" &> /dev/null
    fi
  fi
  # returns either add success, update success or request or update fail
}

function set_access_keys() {
  local access_response_text="$1"

  if [[ ! "${access_response}" =~ oauth_token=(.*)\&oauth_token_secret=(.*)$ ]]; then
    return 1
  fi
  local encoded_access_token="${BASH_REMATCH[1]}"
  if ! set_key etrade_api_token "${encoded_access_token}"; then
    return 1
  fi
echo token

  local encoded_access_secret="${BASH_REMATCH[2]}"
  if ! set_key etrade_api_secret "${encoded_access_secret}"; then
    return 1
  fi
  
  return 0
}

function calculate_hmacsha1_signature() {
  if [[ $# < 5 ]]; then
    echo ${FUNCNAME}: Need 5 parameters, only got $#
    return 1
  fi

  local http_method="$1"
  local request_url="$2"
  local -n request_param_array="$3"
  local consumer_secret="$4"
  local token_secret="$5"

  local ordered_keys=($(printf '%s\n' "${!request_param_array[@]}" | sort))

  local field_key
  local first_loop=true
  local all_param_string=""

  for field_key in "${ordered_keys[@]}"; do
    if ! $first_loop ; then
      all_param_string="${all_param_string}&"
    fi
    first_loop=false

    local param_pair="${field_key}=${request_param_array[${field_key}]}"
    all_param_string="${all_param_string}${param_pair}"
  done

  local encoded_param_string=$(pctEncode ${all_param_string})
  local encoded_request_url=$(pctEncode ${request_url})

  local signature_base_string="${http_method}&${encoded_request_url}&${encoded_param_string}"

  local consumer_secret=$(pctEncode ${consumer_secret})
  local token_secret=$(pctEncode ${token_secret})
  local combined_secret="${consumer_secret}&${token_secret}"

  local calculated_signature=$( \
    echo -n "$signature_base_string" | openssl dgst -sha1 -hmac "${combined_secret}" -binary | base64 \
  )
  local encoded_signature=$(pctEncode ${calculated_signature})

  echo $encoded_signature
}

function http_get() {

  local request_url="$1"
  local -n request_param_array="$2"
  local output_file=""
  if [[ $# > 2 ]]; then
    output_file="$3"
  fi

  local arg_array=("-G")

  local field_key

  for field_key in "${!request_param_array[@]}"; do
    local param_pair="${field_key}=${request_param_array[${field_key}]}"
    arg_array+=("-d")
    arg_array+=("${param_pair}")
  done
  if [ ! -z "${output_file}" ]; then
    arg_array+=("-o")
    arg_array+=("${output_file}")
  fi
  arg_array+=("${request_url}")

  curl "${arg_array[@]}"
}

