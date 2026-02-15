#!/bin/bash

oauth_request_url="https://api.etrade.com/oauth/request_token"
oauth_access_url="https://api.etrade.com/oauth/access_token"
oauth_renew_url="https://api.etrade.com/oauth/renew_access_token"

permanent_key_attr_name="etrade_api_account"
permanent_key_attr_value="etrade_api_account_key"
permanent_key_label="Etrade Account Key"
permanent_secret_attr_value="etrade_api_account_secret"
permanent_secret_label="Etrade Account Secret"

keyring_name="etrade_keyring"

auth_token_keyname="etrade_api_token"
auth_secret_keyname="etrade_api_secret"

function save_account_api_keys() {
  if load_permanent_api_key; then
    echo "This will remove previously saved key/secret, enter 'y' to proceed" > /dev/tty
    IFS= read -r user_confirmation
    if [[ "${user_confirmation}" != y* ]]; then
      echo "Exiting setup" > /dev/tty
      return 1
    fi
  fi

  declare -a key_attributes
  key_attributes+=("${permanent_key_attr_name}")
  key_attributes+=("${permanent_key_attr_value}")

  declare -a secret_attributes
  secret_attributes+=("${permanent_key_attr_name}")
  secret_attributes+=("${permanent_secret_attr_value}")

  set_permanent_key "${permanent_key_label}" "${key_attributes[@]}"

  if [ -z $(get_permanent_key "${key_attributes[@]}") ]; then
    echo "Empty key entered, nothing saved"
    clear_permanent_key "${key_attributes[@]}"
    clear_permanent_key "${secret_attributes[@]}"
    return 1
  fi

  set_permanent_key "${permanent_secret_label}" "${secret_attributes[@]}"

  if [ -z $(get_permanent_key "${secret_attributes[@]}") ]; then
    echo "Empty secret entered, nothing saved"
    clear_permanent_key "${key_attributes[@]}"
    clear_permanent_key "${secret_attributes[@]}"
    return 1
  fi
  return 0
}

function load_permanent_api_key() {
  local retrieved_key retrieved_secret

  if retrieved_key=$(get_permanent_key "${permanent_key_attr_name}" "${permanent_key_attr_value}") && \
     retrieved_secret=$(get_permanent_key "${permanent_key_attr_name}" "${permanent_secret_attr_value}"); then
     export key_value="${retrieved_key}"
     export secret_value="${retrieved_secret}"
     return 0
  fi
  unset key_value
  unset secret_value
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

function set_auth_keys() {
  local access_response_text="$1"

  if [[ ! "${access_response}" =~ oauth_token=(.*)\&oauth_token_secret=(.*)$ ]]; then
    return 1
  fi
  local encoded_access_token="${BASH_REMATCH[1]}"
  local encoded_access_secret="${BASH_REMATCH[2]}"
  if ! set_volatile_key "${keyring_name}" "${auth_token_keyname}" "${encoded_access_token}" || \
     ! set_volatile_key "${keyring_name}" "${auth_secret_keyname}" "${encoded_access_secret}"; then
    return 1
  fi

  return 0
}

function clear_auth_keys() {
  set_persistent_value "time_last_auth" ""
  clear_volatile_keyring "${keyring_name}"
}

function retrieve_auth_keys() {
  # separate declaration and assignment so local doesn't set last return value
  local retrieved_token retrieved_secret
  if retrieved_token=$(get_volatile_key "${auth_token_keyname}") && \
     retrieved_secret=$(get_volatile_key "${auth_secret_keyname}"); then
    export access_token="${retrieved_token}"
    export access_secret="${retrieved_secret}"
    return 0
  fi
  unset access_token
  unset access_secret
  return 1
}

function is_authorization_valid() {
  if ! load_permanent_api_key; then
    echo "Error, need permanent api key"
    return 1
  fi
  if ! retrieve_auth_keys; then
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
  if ! load_permanent_api_key; then
    echo "Error, need permanent api key"
    return 1
  fi
  if ! retrieve_auth_keys; then
    echo "Error, no keys found to renw"
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
  if ! load_permanent_api_key; then
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
  if ! load_permanent_api_key; then
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
    setup)
      save_account_api_keys
      ;;
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
      echo "Authorization renewed at $(date -d @${time_last_auth})"
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