#!/bin/bash

function is_num() {
  if [[ "$1" =~ ^[0-9]+(\.[0-9]*)?$ ]]; then
    return 0
  fi
  return 1
}
