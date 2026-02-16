#!/bin/bash

readonly PERSISTENT_VALUE_FILE="$HOME/.etrade_vars"
readonly DEFAULT_QUOTE_DIR="/dev/shm/.etrade_quotes"

function set_persistent_value() {
  local key="$1"
  local value="$2"
  local file="${PERSISTENT_VALUE_FILE}"

  if [ ! -f "$PERSISTENT_VALUE_FILE" ]; then
    touch "$PERSISTENT_VALUE_FILE"
  fi
  # Remove existing entry for the key
  sed -i "/^$key=/d" "$file"
  # Append new value
  echo "$key=$value" >> "$file"

  source "${PERSISTENT_VALUE_FILE}"
}

function load_persistent_values() {
  if [ -f "$PERSISTENT_VALUE_FILE" ]; then
    source "$PERSISTENT_VALUE_FILE"
  fi
  if [ -z "${QUOTE_DIR}" ]; then
    set_persistent_value "QUOTE_DIR" "$DEFAULT_QUOTE_DIR"
  fi
}
