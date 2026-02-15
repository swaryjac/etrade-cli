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

function set_permanent_key() {
  if [[ $# < 3 ]]; then
    echo "Failed call to set permanent key, needs at least 3 arguments, got $#" 1>&2
    return 1
  fi
  local key_label="$1"
  declare -a secret_tool_params
  secret_tool_params+=("--label='$key_label'")
  shift

  secret_tool_params+=("user")
  secret_tool_params+=("$(whoami)")

  while [ $# -ge 2 ]; do
    secret_tool_params+=("$1")
    secret_tool_params+=("$2")
    shift 2
  done

  echo "Enter key for $key_label:" > /dev/tty
  secret-tool store "${secret_tool_params[@]}"
}

function get_permanent_key() {
  if [[ $# < 2 ]]; then
    echo "Failed call to set permanent key, needs at least 2 arguments, got $#" 1>&2
    return 1
  fi

  declare -a secret_tool_params

  secret_tool_params+=("user")
  secret_tool_params+=("$(whoami)")

  while [ $# -ge 2 ]; do
    secret_tool_params+=("$1")
    secret_tool_params+=("$2")
    shift 2
  done

  secret-tool lookup "${secret_tool_params[@]}"
}

function clear_permanent_key() {
  if [[ $# < 2 ]]; then
    echo "Failed call to clear permanent key, needs at least 2 arguments, got $#" 1>&2
    return 1
  fi

  declare -a secret_tool_params

  secret_tool_params+=("user")
  secret_tool_params+=("$(whoami)")

  while [ $# -ge 2 ]; do
    secret_tool_params+=("$1")
    secret_tool_params+=("$2")
    shift 2
  done

  secret-tool clear "${secret_tool_params[@]}"
}