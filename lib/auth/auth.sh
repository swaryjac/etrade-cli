#!/bin/bash

oauth_request_url="https://api.etrade.com/oauth/request_token"
oauth_access_url="https://api.etrade.com/oauth/access_token"
oauth_renew_url="https://api.etrade.com/oauth/renew_access_token"

keyring_name="etrade_keyring"

auth_token_keyname="etrade_api_token"
auth_secret_keyname="etrade_api_secret"

if ! keyctl list %:${keyring_name} &> /dev/null; then
  keyctl newring ${keyring_name} @u &> /dev/null
fi

function set_persistent_value() {
  local key="$1"
  local value="$2"
  local file="${PERSISTENT_VALUE_FILE}"

  # Remove existing entry for the key
  sed -i "/^$key=/d" "$file"
  # Append new value
  echo "$key=$value" >> "$file"

  source "${PERSISTENT_VALUE_FILE}"
}

function is_num() {
  if [[ "$1" =~ ^[0-9]+(\.[0-9]*)?$ ]]; then
    return 0
  fi
  return 1
}

function authorized_in_last_hour() {
  if [ -n "${time_last_auth}" ] && is_num "${time_last_auth}"; then
    local time_now=$(date +%s)
    local one_hour_ago=$(date -d '1 hour ago' +%s)
    if (( time_last_auth < time_now )) && (( time_last_auth > one_hour_ago )); then
      return 0
    fi
  fi
  return 1
}

function get_permanent_api_key() {
  key_file="api_key.txt"
  secret_file="api_secret.txt"

  if [ -f ${key_file} ]; then
    export key_value=$(cat ${key_file})
  else
    unset key_value
  fi
  if [ -f ${secret_file} ]; then
    export secret_value=$(cat ${secret_file})
  else
    unset secret_value
  fi

  if [[ -z ${key_value} || -z ${secret_value} ]]; then
    return 1
  fi
  return 0
}

function set_volatile_key() {
  local key_name="$1"
  local key_value="$2"
  echo $key_name $key_value
  if ! keyctl add user "${key_name}" "${key_value}" %:${keyring_name} &> /dev/null; then
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

function clear_auth_keys() {
  set_persistent_value "time_last_auth" ""
  keyctl clear %:${keyring_name}
}

function retrieve_auth_keys() {
  # separate declaration and assignment so local doesn't set last return value
  local access_token_id
  access_token_id=$(keyctl request user ${auth_token_keyname} 2>/dev/null)
  if [ $? -eq 0 ]; then
    export access_token=$(keyctl pipe "${access_token_id}")
  else
    unset access_token
    unset access_secret
    return 1
  fi

  local access_secret_id
  access_secret_id=$(keyctl request user ${auth_secret_keyname} 2>/dev/null)
  if [ $? -eq 0 ]; then
    export access_secret=$(keyctl pipe "${access_secret_id}")
  else
    unset access_token
    unset access_secret
    return 1
  fi

  return 0
}

function is_authorization_valid() {
  if ! get_permanent_api_key || ! retrieve_auth_keys; then
    return 1
  fi

  local encoded_access_token="${access_token}"
  local encoded_access_secret="${access_secret}"

  local decoded_access_secret=$(pct_decode ${encoded_access_secret})

  quote_url="${quote_url_base}AA.json"

  detail_flag=FUNDAMENTAL

  declare -A quote_params

  quote_params["detailFlag"]="${detail_flag}"
  quote_params["oauth_token"]="${encoded_access_token}"

  local quote_response="$( \
    send_etrade_query "${quote_url}?detailFlag=${detail_flag}" quote_params "${decoded_access_secret}" \
  )"
  if [[ $? == 0 ]] && echo "${quote_response}" | jq -e 'has("QuoteResponse")' &> /dev/null ; then
    set_persistent_value "time_last_auth" "$(date +%s)"
    return 0
  elif [[ "${quote_response}" == *"token_rejected"* ]]; then
    return 10
  fi
  clear_auth_keys
  return 1
}

function renew_auth_token() {
  if ! retrieve_auth_keys; then
    return 1
  fi

  local encoded_access_token="${access_token}"
  local encoded_access_secret="${access_secret}"

  local decoded_access_secret=$(pct_decode ${encoded_access_secret})

  declare -A authorize_params
  authorize_params["oauth_token"]="${encoded_access_token}"

  local renew_response=$( \
    send_etrade_query "${oauth_renew_url}" authorize_params "${decoded_access_secret}" \
  )

  if [[ $? == 0 && "${renew_response}" == *"renewed"* ]]; then
    set_persistent_value "time_last_auth" "$(date +%s)"
    return 0
  fi
  return 1
}

function get_new_authorization() {
  if ! get_permanent_api_key; then
    echo "Error, need permanent api key"
    return 1
  fi

  # check for existing authorization and revoke?

  #--- Get Request Token ---#
  declare -A request_params

  request_params["oauth_callback"]="oob"

  request_token_response=$(send_etrade_query "${oauth_request_url}" request_params "no_secret")

  if [[ "${request_token_response}" =~ oauth_token=(.*)\&oauth_token_secret=(.*)\&oauth_callback_confirmed.* ]]; then
    encoded_request_token="${BASH_REMATCH[1]}"
    encoded_request_secret="${BASH_REMATCH[2]}"
  else
    echo "${request_token_response}" > request_response.txt
    echo "response parsing failed, output in request_response.txt"
    return 1
  fi

  decoded_request_token=$(pct_decode ${encoded_request_token})
  decoded_request_secret=$(pct_decode ${encoded_request_secret})

  #--- User login and get access code ---#
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
    return 1
  fi

  #--- Use access code to get authorization ---#
  declare -A authorize_params

  authorize_params["oauth_token"]="${encoded_request_token}"
  authorize_params["oauth_verifier"]="${verification_code}"

  access_response=$(send_etrade_query "${oauth_access_url}" authorize_params ${decoded_request_secret})

  if ! set_auth_keys "${access_response}"; then
    echo "response parsing failed, response text:"
    echo "${access_response}"
    return 1
  fi

  retrieve_auth_keys

  set_persistent_value "time_last_auth" "$(date +%s)"
  return 0
}

function has_or_get_authorization() {
  if ! get_permanent_api_key; then
    echo "Error, need permanent api key"
    return 1
  elif { authorized_in_last_hour && retrieve_auth_keys; } || \
       { is_authorization_valid || { [[ $? == 10 ]] && renew_auth_token; }; }; then
    echo "Authorization valid as of $(date -d @${time_last_auth})"
    return 0
  fi
  get_new_authorization
}

function execute_auth() {
  subcommand=$1
  case "$subcommand" in
    # setup)
    #   ;;
    check)
      if is_authorization_valid; then
        echo "Currently Authorized"
        return 0
      elif [[ $? == 10 ]]; then
        echo "Authorization timed out"
        return 10
      else
        echo "No Current Authorization"
        return 1
      fi
      ;;
    renew)
      if ! renew_auth_token; then
        echo "Renewal failed!"
        return 1
      fi
      return 0
      ;;
    get)
      has_or_get_authorization
      ;;
    force)
      get_new_authorization
      ;;
    revoke)
      clear_auth_keys
      ;;
    *)
      echo "Bad subcommand"
      return 1
      ;;
  esac

}