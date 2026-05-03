#!/bin/bash

permanent_key_attr_name="etrade_api_account"
permanent_key_attr_value="etrade_api_account_key"
permanent_key_label="Etrade Account Key"
permanent_secret_attr_value="etrade_api_account_secret"
permanent_secret_label="Etrade Account Secret"

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
    echo "Failed call to get permanent key, needs at least 2 arguments, got $#" 1>&2
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

function save_account_api_keys() {
  local permanent_key_attr_value permanent_secret_attr_value
  if [[ "${ETRADE_ENV:-production}" == "sandbox" ]]; then
    permanent_key_attr_value="etrade_sandbox_api_account_key"
    permanent_secret_attr_value="etrade_sandbox_api_account_secret"
  else
    permanent_key_attr_value="etrade_api_account_key"
    permanent_secret_attr_value="etrade_api_account_secret"
  fi

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
  local permanent_key_attr_value permanent_secret_attr_value
  if [[ "${ETRADE_ENV:-production}" == "sandbox" ]]; then
    permanent_key_attr_value="etrade_sandbox_api_account_key"
    permanent_secret_attr_value="etrade_sandbox_api_account_secret"
  else
    permanent_key_attr_value="etrade_api_account_key"
    permanent_secret_attr_value="etrade_api_account_secret"
  fi

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
