#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures"

setup() {
  export PARENT_PATH="$REPO_ROOT"
  export CACHE_DIR="$FIXTURES_DIR"

  source "$PARENT_PATH/lib/common/validation.sh"
  source "$PARENT_PATH/lib/quote/quote.sh"
  source "$REPO_ROOT/tests/mocks.sh"
}

# ─── get_quote_price ──────────────────────────────────────────────────────────

@test "get_quote_price: returns correct price from cache (PLTR)" {
  run get_quote_price -r PLTR
  [ "$status" -eq 0 ]
  [ "$output" = "146.45" ]
}

@test "get_quote_price: fails when cache file does not exist" {
  run get_quote_price -r NOPE
  [ "$status" -ne 0 ]
}

@test "get_quote_price: fails for invalid ticker symbol" {
  run get_quote_price -r "abc123"
  [ "$status" -ne 0 ]
}

# ─── get_quote_option ────────────────────────────────────────────────────────

@test "get_quote_option: returns JSON with OptionChainResponse from cache (PLTR)" {
  run get_quote_option -r PLTR
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("OptionChainResponse")' > /dev/null
}

@test "get_quote_option: fails when cache file does not exist" {
  run get_quote_option -r NOPE
  [ "$status" -ne 0 ]
}

@test "get_quote_option: fails for invalid ticker symbol" {
  run get_quote_option -r "abc123"
  [ "$status" -ne 0 ]
}

# ─── expiry validation ────────────────────────────────────────────────────────

@test "get_quote_option: rejects invalid expiry date" {
  mock_auth_success
  run get_quote_option -s 100 -x "not-a-date" PLTR
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid expiry date"* ]]
}

@test "get_quote_option: accepts valid expiry date" {
  mock_auth_success
  mock_api_empty
  run get_quote_option -s 100 -x "2026-05-02" PLTR
  [ "$status" -eq 0 ]
}

# ─── get_quote (non-cache path) ──────────────────────────────────────────────

@test "get_quote: returns JSON when API response has QuoteResponse" {
  mock_auth_success
  mock_api_returns "$FIXTURES_DIR/PLTR.json"
  run get_quote PLTR
  [ "$status" -eq 0 ]
  [[ "$output" == *'"QuoteResponse"'* ]]
}

@test "get_quote: fails when API response lacks QuoteResponse" {
  mock_auth_success
  mock_api_empty
  run get_quote PLTR
  [ "$status" -ne 0 ]
}

@test "get_quote: fails when auth fails" {
  mock_auth_failure
  run get_quote PLTR
  [ "$status" -ne 0 ]
}

# ─── get_quote_option (non-cache path) ───────────────────────────────────────

@test "get_quote_option: returns option JSON when API succeeds" {
  mock_auth_success
  mock_api_returns "$FIXTURES_DIR/PLTR_opt.json"
  run get_quote_option -s 100 PLTR
  [ "$status" -eq 0 ]
  [[ "$output" == *'"OptionChainResponse"'* ]]
}

@test "get_quote_option: uses get_quote_price for strike when -s not given" {
  mock_auth_success
  mock_quote_price "146.45"
  mock_api_returns "$FIXTURES_DIR/PLTR_opt.json"
  run get_quote_option PLTR
  [ "$status" -eq 0 ]
}

@test "get_quote_option: fails when auth fails" {
  mock_auth_failure
  run get_quote_option -s 100 PLTR
  [ "$status" -ne 0 ]
}

@test "get_quote_option: fails when QUOTE_NUM_STRIKES is non-numeric" {
  mock_auth_success
  export QUOTE_NUM_STRIKES="abc"
  run get_quote_option -s 100 PLTR
  [ "$status" -ne 0 ]
  [[ "$output" == *"Illegal number of strikes"* ]]
}

# ─── get_quote_batch ─────────────────────────────────────────────────────────

@test "get_quote_batch: writes quote cache file for symbol" {
  export CACHE_DIR="$BATS_TEST_TMPDIR"
  mock_auth_success
  mock_api_returns "$FIXTURES_DIR/PLTR.json"
  echo "PLTR" | get_quote_batch
  [ -f "$(get_quote_filename PLTR)" ]
}

@test "get_quote_batch: retries on failure and eventually succeeds" {
  export CACHE_DIR="$BATS_TEST_TMPDIR"
  mock_auth_success
  mock_api_fails_once_then_returns "$FIXTURES_DIR/PLTR.json"
  mock_no_sleep
  echo "PLTR" | get_quote_batch
  [ -f "$(get_quote_filename PLTR)" ]
}
