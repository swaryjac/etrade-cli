#!/bin/bash

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