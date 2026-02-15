#!/bin/bash

PERSISTENT_VALUE_FILE="$HOME/.etrade_vars"

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
    set_persistent_value "QUOTE_DIR" "/dev/shm/.etrade_quotes"
  fi
}

function get_all_saved_option_file_symbols() {
  local path_name
  for path_name in ${QUOTE_DIR}/*_opt.json; do
    local file_name_only="${path_name##*/}"
    echo "${file_name_only%_opt.json}"
  done
}

function get_quote_filename() {
  local symbol=$1
  echo "${QUOTE_DIR}/${symbol}.json"
}

function get_option_filename() {
  local symbol=$1
  echo "${QUOTE_DIR}/${symbol}_opt.json"
}

function quote_file_exists() {
  local symbol=$1
  if is_ticker_symbol_valid "$symbol" && [ -f "$(get_quote_filename $symbol)" ]; then
    return 0
  fi
  return 1
}

function option_file_exists() {
  local symbol=$1
  if is_ticker_symbol_valid "$symbol" && [ -f "$(get_option_filename $symbol)" ]; then
    return 0
  fi
  return 1
}
