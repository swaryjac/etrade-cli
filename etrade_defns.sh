#!/bin/bash

oauth_request_url="https://api.etrade.com/oauth/request_token"
oauth_access_url="https://api.etrade.com/oauth/access_token"
oauth_renew_url="https://api.etrade.com/oauth/renew_access_token"

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

auth_token_keyname="etrade_api_token"
auth_secret_keyname="etrade_api_secret"

function set_volatile_key() {
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

function set_auth_keys() {
  local access_response_text="$1"

  if [[ ! "${access_response}" =~ oauth_token=(.*)\&oauth_token_secret=(.*)$ ]]; then
    return 1
  fi
  local encoded_access_token="${BASH_REMATCH[1]}"
  if ! set_volatile_key ${auth_token_keyname} "${encoded_access_token}"; then
    return 1
  fi

  local encoded_access_secret="${BASH_REMATCH[2]}"
  if ! set_volatile_key ${auth_secret_keyname} "${encoded_access_secret}"; then
    return 1
  fi

  return 0
}

function retrieve_auth_keys() {
  local access_token_id=$(keyctl request user ${auth_token_keyname} 2>/dev/null)
  if [ $? -eq 0 ]; then
    export access_token=$(keyctl pipe "${access_token_id}")
  else
    unset access_token
    unset access_secret
    return 1
  fi

  local access_secret_id=$(keyctl request user ${auth_secret_keyname} 2>/dev/null)
  if [ $? -eq 0 ]; then
    export access_secret=$(keyctl pipe "${access_secret_id}")
  else
    unset access_token
    unset access_secret
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
  # signature only uses base url, if url contains parameters, remove them
  local request_url="${2%\?*}"
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

  local ordered_keys=($(printf '%s\n' "${!request_param_array[@]}" | sort))

  local field_key

  for field_key in "${ordered_keys[@]}"; do
    local param_pair="${field_key}=${request_param_array[${field_key}]}"
    arg_array+=("-d")
    arg_array+=("${param_pair}")
  done

  local temp_response_file="/dev/shm/get_response.html"
  arg_array+=("-o")
  if [ ! -z "${output_file}" ]; then
    arg_array+=("${output_file}")
  else
    arg_array+=("${temp_response_file}")
  fi
  arg_array+=("-w")
  arg_array+=("%{http_code}")
  arg_array+=("${request_url}")

  http_status=$(curl "${arg_array[@]}")

  if [ -z "${output_file}" ]; then
    cat ${temp_response_file}
  fi
  if [[ "${http_status}" == "200" ]]; then
    return 0
  fi
  return 1
}

function send_etrade_query() {
  local request_url="$1"
  local -n query_param_array="$2"
  local decoded_request_secret="$3"
  local output_file=""
  if [[ $# > 3 ]]; then
    output_file="$4"
  fi

  local http_method=GET

  local timestamp=$(date +%s)
  local nonce=$(date +%s%T | openssl base64 | sed -e 's/[+=/]//g')

  query_param_array["oauth_consumer_key"]="${key_value}"
  query_param_array["oauth_nonce"]="${nonce}"
  query_param_array["oauth_signature_method"]="HMAC-SHA1"
  query_param_array["oauth_timestamp"]="${timestamp}"

  local encoded_request_signature=$( \
    calculate_hmacsha1_signature ${http_method} "${request_url}" query_param_array "${secret_value}" "${decoded_request_secret}" \
  )

  query_param_array["oauth_signature"]="${encoded_request_signature}"

  # After using for signature calc, remove parameters from the header that appear in the url request
  local params_in_url=$( \
    echo ${request_url} | awk '{
      while(match($0, /[^?&]*=[^&]*/)) {
        print substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART + RLENGTH)
      }
    }' \
  )

  for param_pair in ${params_in_url}; do
    if [[ "${param_pair}" =~ (.*)=(.*) ]]; then
      unset "query_param_array["${BASH_REMATCH[1]}"]"
    fi
  done

  http_get "${request_url}" query_param_array "${output_file}"
}

function is_authorization_valid() {
  if ! retrieve_auth_keys; then
    return 1
  fi

  local encoded_access_token="${access_token}"
  local encoded_access_secret="${access_secret}"

  local decoded_access_secret=$(pctDecode ${encoded_access_secret})

  quote_url="${quote_url_base}AA.json"

  detail_flag=FUNDAMENTAL

  declare -A quote_params

  quote_params["detailFlag"]="${detail_flag}"
  quote_params["oauth_token"]="${encoded_access_token}"

  local quote_response="$( \
    send_etrade_query "${quote_url}?detailFlag=${detail_flag}" quote_params "${decoded_access_secret}" \
  )"
  if [[ $? == 0 ]] && echo "${quote_response}" | jq -e 'has("QuoteResponse")' ; then
    return 0
  elif [[ "${quote_response}" == *"token_rejected"* ]]; then
    return 10
  fi
  return 1
}

function renew_auth_token() {
  if ! retrieve_auth_keys; then
    return 1
  fi

  local encoded_access_token="${access_token}"
  local encoded_access_secret="${access_secret}"

  local decoded_access_secret=$(pctDecode ${encoded_access_secret})

  declare -A authorize_params
  authorize_params["oauth_token"]="${encoded_access_token}"

  local renew_response=$( \
    send_etrade_query "${oauth_renew_url}" authorize_params "${decoded_access_secret}" \
  )

  echo ${renew_response} > renew_response.txt
}
