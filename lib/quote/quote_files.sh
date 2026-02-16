#!/bin/bash

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
