#!/bin/bash

mock_auth_success() {
  import_secret_variables() {
    access_token="test_token"
    decoded_access_secret="test_secret"
    return 0
  }
}

mock_auth_failure() {
  import_secret_variables() {
    echo "Error: No Authorization available"
    return 1
  }
}

mock_api_returns() {
  _mock_fixture="$1"
  send_etrade_query() { cat "$_mock_fixture"; }
}

mock_api_empty() {
  send_etrade_query() { echo "{}"; }
}

mock_api_error() {
  send_etrade_query() { return 1; }
}

# Fails on the first call, returns fixture on all subsequent calls.
# Uses a temp file as counter so the state survives command-substitution subshells.
mock_api_fails_once_then_returns() {
  _mock_fixture="$1"
  _mock_counter_file=$(mktemp)
  echo 0 > "$_mock_counter_file"
  send_etrade_query() {
    local count
    count=$(cat "$_mock_counter_file")
    count=$((count + 1))
    echo "$count" > "$_mock_counter_file"
    [ "$count" -le 1 ] && return 1
    cat "$_mock_fixture"
  }
}

mock_quote_price() {
  _mock_price="$1"
  get_quote_price() { echo "$_mock_price"; }
}

mock_no_sleep() {
  sleep() { :; }
}
