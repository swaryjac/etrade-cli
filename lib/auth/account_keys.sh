#!/bin/bash

permanent_key_attr_name="etrade_api_account"
permanent_key_attr_value="etrade_api_account_key"
permanent_key_label="Etrade Account Key"
permanent_secret_attr_value="etrade_api_account_secret"
permanent_secret_label="Etrade Account Secret"

_creds_file="${XDG_CONFIG_HOME:-$HOME/.config}/etrade/credentials"

function _read_creds_file() {
  local key="$1"
  [ -f "$_creds_file" ] || return 1
  local val
  val=$(grep "^${key}=" "$_creds_file" 2>/dev/null | cut -d= -f2-)
  [ -n "$val" ] || return 1
  echo "$val"
}

function _write_creds_file() {
  local key="$1" value="$2"
  mkdir -p "$(dirname "$_creds_file")"
  local existing
  existing=$(grep -v "^${key}=" "$_creds_file" 2>/dev/null || true)
  {
    [[ -n "$existing" ]] && printf '%s\n' "$existing"
    printf '%s=%s\n' "$key" "$value"
  } > "$_creds_file"
  chmod 600 "$_creds_file"
}

function _clear_creds_file() {
  local key="$1"
  [ -f "$_creds_file" ] || return 0
  local remaining
  remaining=$(grep -v "^${key}=" "$_creds_file" 2>/dev/null || true)
  printf '%s\n' "$remaining" > "$_creds_file"
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

function _store_to_keyring() {
  local label="$1" value="$2"
  shift 2
  local -a params
  params+=("--label=$label" "user" "$(whoami)")
  while [ $# -ge 2 ]; do
    params+=("$1" "$2")
    shift 2
  done
  printf '%s' "$value" | secret-tool store "${params[@]}" 2>/dev/null
}

function save_account_api_keys() {
  local permanent_key_attr_value permanent_secret_attr_value permanent_key_label permanent_secret_label
  local creds_key_name creds_secret_name

  if [[ "${ETRADE_ENV:-production}" == "sandbox" ]]; then
    permanent_key_attr_value="etrade_sandbox_api_account_key"
    permanent_secret_attr_value="etrade_sandbox_api_account_secret"
    permanent_key_label="Etrade Sandbox Account Key"
    permanent_secret_label="Etrade Sandbox Account Secret"
    creds_key_name="ETRADE_SANDBOX_API_KEY"
    creds_secret_name="ETRADE_SANDBOX_API_SECRET"
  else
    permanent_key_attr_value="etrade_api_account_key"
    permanent_secret_attr_value="etrade_api_account_secret"
    permanent_key_label="Etrade Account Key"
    permanent_secret_label="Etrade Account Secret"
    creds_key_name="ETRADE_API_KEY"
    creds_secret_name="ETRADE_API_SECRET"
  fi

  if load_permanent_api_key; then
    echo "This will remove previously saved key/secret, enter 'y' to proceed" > /dev/tty
    IFS= read -r user_confirmation
    if [[ "${user_confirmation}" != y* ]]; then
      echo "Exiting setup" > /dev/tty
      return 1
    fi
  fi

  local entered_key entered_secret

  printf "Enter %s: " "${permanent_key_label}" > /dev/tty
  IFS= read -rs entered_key
  echo > /dev/tty

  if [[ -z "$entered_key" ]]; then
    echo "Empty key entered, nothing saved"
    return 1
  fi

  printf "Enter %s: " "${permanent_secret_label}" > /dev/tty
  IFS= read -rs entered_secret
  echo > /dev/tty

  if [[ -z "$entered_secret" ]]; then
    echo "Empty secret entered, nothing saved"
    return 1
  fi

  if _store_to_keyring "$permanent_key_label" "$entered_key" \
       "$permanent_key_attr_name" "$permanent_key_attr_value" && \
     _store_to_keyring "$permanent_secret_label" "$entered_secret" \
       "$permanent_key_attr_name" "$permanent_secret_attr_value"; then
    printf "Credentials stored in keyring\n" > /dev/tty
  else
    clear_permanent_key "$permanent_key_attr_name" "$permanent_key_attr_value" 2>/dev/null
    clear_permanent_key "$permanent_key_attr_name" "$permanent_secret_attr_value" 2>/dev/null
    printf "Note: storing credentials in %s (chmod 600)\n" "$_creds_file" > /dev/tty
    _write_creds_file "$creds_key_name" "$entered_key"
    _write_creds_file "$creds_secret_name" "$entered_secret"
  fi

  return 0
}

function _key_storage_status() {
  local key_attr_value="$1" secret_attr_value="$2"
  local creds_key_name="$3" creds_secret_name="$4"
  local key_status secret_status val

  if val=$(get_permanent_key "${permanent_key_attr_name}" "${key_attr_value}" 2>/dev/null) && [[ -n "$val" ]]; then
    key_status="(stored in keyring)"
  elif _read_creds_file "$creds_key_name" &>/dev/null; then
    key_status="(stored in credentials file)"
  else
    key_status="(not stored)"
  fi

  if val=$(get_permanent_key "${permanent_key_attr_name}" "${secret_attr_value}" 2>/dev/null) && [[ -n "$val" ]]; then
    secret_status="(stored in keyring)"
  elif _read_creds_file "$creds_secret_name" &>/dev/null; then
    secret_status="(stored in credentials file)"
  else
    secret_status="(not stored)"
  fi

  printf '%s\n%s\n' "$key_status" "$secret_status"
}

function show_stored_keys() {
  local env env_label key_attr_value secret_attr_value creds_key_name creds_secret_name
  local key_status secret_status statuses

  for env in production sandbox; do
    if [[ "$env" == "sandbox" ]]; then
      env_label="Sandbox"
      key_attr_value="etrade_sandbox_api_account_key"
      secret_attr_value="etrade_sandbox_api_account_secret"
      creds_key_name="ETRADE_SANDBOX_API_KEY"
      creds_secret_name="ETRADE_SANDBOX_API_SECRET"
    else
      env_label="Production"
      key_attr_value="etrade_api_account_key"
      secret_attr_value="etrade_api_account_secret"
      creds_key_name="ETRADE_API_KEY"
      creds_secret_name="ETRADE_API_SECRET"
    fi

    statuses=$(_key_storage_status "$key_attr_value" "$secret_attr_value" "$creds_key_name" "$creds_secret_name")
    key_status=$(sed -n '1p' <<< "$statuses")
    secret_status=$(sed -n '2p' <<< "$statuses")

    printf "%-10s %-7s %s\n" "${env_label}" "key:"    "${key_status}"
    printf "%-10s %-7s %s\n" "${env_label}" "secret:" "${secret_status}"
    echo
  done
}

function load_permanent_api_key() {
  local permanent_key_attr_value permanent_secret_attr_value
  local creds_key_name creds_secret_name

  if [[ "${ETRADE_ENV:-production}" == "sandbox" ]]; then
    permanent_key_attr_value="etrade_sandbox_api_account_key"
    permanent_secret_attr_value="etrade_sandbox_api_account_secret"
    creds_key_name="ETRADE_SANDBOX_API_KEY"
    creds_secret_name="ETRADE_SANDBOX_API_SECRET"
  else
    permanent_key_attr_value="etrade_api_account_key"
    permanent_secret_attr_value="etrade_api_account_secret"
    creds_key_name="ETRADE_API_KEY"
    creds_secret_name="ETRADE_API_SECRET"
  fi

  local retrieved_key retrieved_secret

  # Env vars — highest priority, for CI or manual override
  if [[ -n "${!creds_key_name}" && -n "${!creds_secret_name}" ]]; then
    export key_value="${!creds_key_name}"
    export secret_value="${!creds_secret_name}"
    return 0
  fi

  # Keyring
  if retrieved_key=$(get_permanent_key "${permanent_key_attr_name}" "${permanent_key_attr_value}" 2>/dev/null) && \
     retrieved_secret=$(get_permanent_key "${permanent_key_attr_name}" "${permanent_secret_attr_value}" 2>/dev/null) && \
     [[ -n "$retrieved_key" && -n "$retrieved_secret" ]]; then
    export key_value="${retrieved_key}"
    export secret_value="${retrieved_secret}"
    return 0
  fi

  # Credentials file
  if retrieved_key=$(_read_creds_file "$creds_key_name") && \
     retrieved_secret=$(_read_creds_file "$creds_secret_name"); then
    export key_value="${retrieved_key}"
    export secret_value="${retrieved_secret}"
    return 0
  fi

  unset key_value
  unset secret_value
  return 1
}
