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

mock_api_captures_url() {
  _mock_fixture="$1"
  _mock_captured_url_file=$(mktemp)
  send_etrade_query() {
    echo "$1" > "$_mock_captured_url_file"
    cat "$_mock_fixture"
  }
}

# Faithful E*TRADE transactions pagination mock for marker-based sync.
# $1 = path to a JSON array of raw transaction records (each with transactionId
# and transactionDate in ms). The mock filters to [startDate,endDate] (MMDDYYYY,
# resolved in ET inclusively), sorts by transactionId DESC, and pages by the
# INCLUSIVE `marker` cursor ("<id>_<epoch_seconds>"): a request carrying marker M
# returns records with id <= M. Each response's `marker` is the last (lowest-id)
# record returned, and `next` is present only while records remain strictly below
# it -- so consecutive pages overlap by one record (which ingest dedups), exactly
# like the real API. `moreTransactions` is always false, also like the real API.
mock_marker_api() {
  _mock_dataset="$1"
  send_etrade_query() {
    local -n _p="$2"
    python3 - "$_mock_dataset" "${_p[startDate]}" "${_p[endDate]}" "${_p[count]}" "${_p[marker]:-}" "$4" <<'PY'
import json, sys
from datetime import datetime
from zoneinfo import ZoneInfo
ET = ZoneInfo("America/New_York")
recs = json.load(open(sys.argv[1]))
start, end, count, marker, out = sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5], sys.argv[6]
def d(s): return datetime.strptime(s, "%m%d%Y").date()
def ed(ms): return datetime.fromtimestamp(int(ms) / 1000, ET).date()
s, e = d(start), d(end)
inr = [r for r in recs if s <= ed(r["transactionDate"]) <= e]
inr.sort(key=lambda r: int(r["transactionId"]), reverse=True)
if marker:
    mid = int(marker.split("_")[0])
    inr = [r for r in inr if int(r["transactionId"]) <= mid]
page = inr[:count]
resp = {"Transaction": page, "moreTransactions": False, "transactionCount": len(page)}
if page:
    last = page[-1]
    resp["marker"] = f'{last["transactionId"]}_{int(last["transactionDate"]) // 1000}'
    if any(int(r["transactionId"]) < int(last["transactionId"]) for r in inr):
        resp["next"] = "https://api.etrade.com/next?marker=" + resp["marker"]
json.dump({"TransactionListResponse": resp}, open(out, "w"))
PY
  }
}
