#!/bin/bash

source "$PARENT_PATH/lib/auth/account_keys.sh"
source "$PARENT_PATH/lib/auth/authorization_keys.sh"

function authorized_in_last_hour() {
  get_auth_time > /dev/null 2>&1
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

  local quote_url="https://$(etrade_api_host)/v1/market/quote/AA.json"

  local detail_flag=FUNDAMENTAL

  declare -A quote_params

  quote_params["detailFlag"]="${detail_flag}"
  quote_params["oauth_token"]="${encoded_access_token}"

  echo "Checking authorization validity"

  local quote_response="$( \
    send_etrade_query "${quote_url}?detailFlag=${detail_flag}" quote_params "${decoded_access_secret}" \
  )"
  if [[ $? == 0 ]] && echo "${quote_response}" | jq -e 'has("QuoteResponse")' &> /dev/null ; then
    set_auth_time
    return 0
  elif [[ "${quote_response}" == *"token_rejected"* ]]; then
    return 10
  fi
  clear_auth_keys
  return 1
}

function check_authorization() {
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

  echo "Renewing Authorization"

  local oauth_renew_url="https://$(etrade_api_host)/oauth/renew_access_token"

  local renew_response=$( \
    send_etrade_query "${oauth_renew_url}" authorize_params "${decoded_access_secret}" \
  )

  if [[ $? == 0 && "${renew_response}" == *"renewed"* ]]; then
    set_auth_time
    echo "Authorization renewed at $(date -d @"$(get_auth_time)")"
    return 0
  fi
  echo "Renewal failed!"
  return 1
}

function get_new_authorization() {
  if ! load_permanent_api_key; then
    echo "Error, need permanent api key"
    return 1
  fi

  local oauth_request_url="https://$(etrade_api_host)/oauth/request_token"
  local oauth_access_url="https://$(etrade_api_host)/oauth/access_token"
  local user_auth_url="https://us.etrade.com/e/t/etws/authorize"

  # check for existing authorization and revoke?

  #--- Get Request Token ---#
  declare -A request_params

  request_params["oauth_callback"]="oob"

  echo "Requesting token"

  local request_token_response=$( \
    send_etrade_query "${oauth_request_url}" request_params "no_secret" \
  )

  if [[ "${request_token_response}" =~ oauth_token=(.*)\&oauth_token_secret=(.*)\&oauth_callback_confirmed.* ]]; then
    local encoded_request_token="${BASH_REMATCH[1]}"
    local encoded_request_secret="${BASH_REMATCH[2]}"
  else
    echo "response parsing failed:" >&2
    echo "${request_token_response}" >&2
    return 1
  fi

  local decoded_request_token=$(pct_decode ${encoded_request_token})
  local decoded_request_secret=$(pct_decode ${encoded_request_secret})

  #--- User login and get access code ---#
  local authorize_url="${user_auth_url}?key=${key_value}&token=${encoded_request_token}"

  echo "" > /dev/tty
  echo "************************************" > /dev/tty
  if command -v xdg-open &> /dev/null; then
    xdg-open "${authorize_url}" &> /dev/null &
    echo "If browser page didn't load, go to:" > /dev/tty
  fi
  echo "${authorize_url}" > /dev/tty
  echo "************************************" > /dev/tty
  echo "" > /dev/tty

  read -p "Input verification code: " verification_code
  if [ -z "$verification_code" ]; then
    echo "no code entered"
    return 1
  fi

  #--- Use access code to get authorization ---#
  declare -A authorize_params

  authorize_params["oauth_token"]="${encoded_request_token}"
  authorize_params["oauth_verifier"]="${verification_code}"

  echo "Requesting Authorization"

  local access_response=$( \
    send_etrade_query "${oauth_access_url}" authorize_params ${decoded_request_secret} \
  )

  if ! set_auth_keys "${access_response}"; then
    echo "Response parsing failed, response text:"
    echo "${access_response}"
    return 1
  fi

  retrieve_auth_keys

  set_auth_time
  return 0
}

function has_or_get_authorization() {
  if ! load_permanent_api_key; then
    echo "Error, need permanent api key"
    return 1
  elif authorized_in_last_hour && retrieve_auth_keys; then
    echo "Authorization valid as of $(date -d @"$(get_auth_time)")"
    return 0
  elif is_authorization_valid; then
    echo "Authorization valid as of $(date -d @"$(get_auth_time)")"
    return 0
  elif [[ $? == 10 ]] && renew_auth_token; then
    return 0
  fi
  get_new_authorization
}

function usage_auth() {
  printf "Usage:\n"
  printf "\tetrade auth {-h --help}\n"
  printf "\tetrade auth <subcommand>\n\n"
  printf "Subcommand:\n"
  subcmd_len=6
  sec_line_indent=$((subcmd_len + 3))
  printf "\t%-${subcmd_len}s - %s\n" "setup" \
           "Enter your Etrade Account API key and secret for storage in gnome-keyring"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "Required for authorization to perform all quote operations"
  printf "\n"
  printf "\t%-${subcmd_len}s - %s\n" "check" \
           "Print the current authorization status:"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "No held account key, No authorization token, token timed out (can be renewed)"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "token expired, or token held and currently authorized"
  printf "\n"
  printf "\t%-${subcmd_len}s - %s\n" "renew" \
           "Attempt to renew the current authorization token"
  printf "\n"
  printf "\t%-${subcmd_len}s - %s\n" "get" \
           "Gets a new authorization token, if required"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "Attempts to renew token if it is timed out"
  printf "\t%${sec_line_indent}s%s\n" " " \
           "Prints time of last authorization if still valid"
  printf "\n"
  printf "\t%-${subcmd_len}s - %s\n" "force" \
           "Gets a new authorization token, no matter the status of any currently held token"
  printf "\n"
  printf "\t%-${subcmd_len}s - %s\n" "revoke" \
           "Delete any held authorization token"
}

function help_auth() {
  printf "Etrade CLI Authorization\n"
  printf "\tAuthorizes use of the Etrade API for an account with an access key/secret\n"
  printf "\tManages Etrade developer account token/secret using gnome-keyring\n"
  printf "\tRequests authorization and manages tokens in Linux keyctl keyring\n"
  printf "\tRequires user to follow link, sign in, accept use, and paste code into CLI\n"
  printf "\tAuthorization must be obtained in order to use the Etrade CLI quote operations\n"
  printf "\n"
  usage_auth
}

function execute_auth() {
  local subcommand=$1
  case "$subcommand" in
    setup)
      save_account_api_keys
      ;;
    check)
      check_authorization
      ;;
    renew)
      renew_auth_token
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
    -h|--help)
      help_auth
      ;;
    *)
      printf "Unrecognized subcommand '${subcommand}'\n\n" 1>&2
      usage_auth 1>&2
      return 1
      ;;
  esac

}