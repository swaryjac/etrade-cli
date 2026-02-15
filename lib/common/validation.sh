#!/bin/bash

function is_num() {
  if [[ "$1" =~ ^[0-9]+(\.[0-9]*)?$ ]]; then
    return 0
  fi
  return 1
}

function is_ticker_symbol_valid() {
  if [ -n $1 ] && [[ "$1" =~ [A-Z]{1,5} ]]; then
    return 0
  fi
  return 1
}
