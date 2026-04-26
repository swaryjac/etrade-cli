#!/bin/bash

keyring_name="etrade_keyring"

auth_token_keyname="etrade_api_token"
auth_secret_keyname="etrade_api_secret"
auth_time_keyname="etrade_auth_time"
auth_validity_seconds=3600

function set_volatile_key() {
  local keyring="$1"
  local key_name="$2"
  local key_value="$3"

  if ! keyctl list %:${keyring_name} &> /dev/null; then
    keyctl newring ${keyring_name} @u &> /dev/null
  fi

  if ! keyctl add user "${key_name}" "${key_value}" %:${keyring} &> /dev/null; then
    local key_id
    if key_id=$(keyctl request user "${key_name}" 2&>1); then
      keyctl update "${key_id}" "${key_value}" &> /dev/null
    fi
  fi
  # returns either add success, update success or request or update fail
}

function get_volatile_key() {
  local key_name="$1"

  local key_id=$(keyctl request user ${key_name} 2>/dev/null)
  if [[ $? == 0 && ! -z "${key_id}" ]]; then
    if keyctl pipe "${key_id}" 2> /dev/null; then
      return 0
    fi
  fi
  return 1
}

function clear_volatile_keyring() {
  local keyring="$1"

  keyctl clear %:${keyring}
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

function set_auth_time() {
  set_volatile_key "${keyring_name}" "${auth_time_keyname}" "$(date +%s)"
  local key_id
  if key_id=$(keyctl request user "${auth_time_keyname}" 2>/dev/null); then
    keyctl timeout "${key_id}" "${auth_validity_seconds}" &>/dev/null
  fi
}

function get_auth_time() {
  get_volatile_key "${auth_time_keyname}"
}

function clear_auth_keys() {
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
