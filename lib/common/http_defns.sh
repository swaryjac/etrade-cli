#!/bin/bash

function pct_encode() {
  local is_debug_on=false
  if [[ "$-" == *x* ]]; then
    set +x
    is_debug_on=true
  fi

  local length="${#1}"
  for ((n = 0; n < length; n++)); do
    local c="${1:n:1}"
    case $c in
      [a-zA-Z0-9.~_-]) printf "$c" ;;
                    *) printf '%%%02X' "'$c"
    esac
  done

  if $is_debug_on; then
    set -x
  fi
}

function pct_decode() {
  local is_debug_on=false
  if [[ "$-" == *x* ]]; then
    set +x
    is_debug_on=true
  fi

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
  if [ -n "${strg}" ] ; then pct_decode "${strg}"; fi

  if $is_debug_on; then
    set -x
  fi
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
    if $first_loop ; then
      first_loop=false
    else
      all_param_string="${all_param_string}&"
    fi

    local param_pair="${field_key}=${request_param_array[${field_key}]}"
    all_param_string="${all_param_string}${param_pair}"
  done

  local encoded_param_string=$(pct_encode ${all_param_string})
  local encoded_request_url=$(pct_encode ${request_url})

  local signature_base_string="${http_method}&${encoded_request_url}&${encoded_param_string}"

  local consumer_secret=$(pct_encode ${consumer_secret})
  local token_secret=$(pct_encode ${token_secret})
  local combined_secret="${consumer_secret}&${token_secret}"

  local calculated_signature=$( \
    echo -n "$signature_base_string" | openssl dgst -sha1 -hmac "${combined_secret}" -binary | base64 \
  )
  local encoded_signature=$(pct_encode ${calculated_signature})

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

  local http_status=$(curl "${arg_array[@]}" 2> /dev/null)

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

  if [[ -z ${secret_value} || -z ${decoded_request_secret} ]]; then
    echo "ERROR: Missing api or authorization secret"
    return 1
  elif [[ "${decoded_request_secret}" == "no_secret" ]]; then
    decoded_request_secret=""
  fi

  local http_method=GET

  local timestamp=$(date +%s)
  local nonce=$(date +%s%N | openssl base64 | sed -e 's/[+=/]//g')

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
