#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures"

setup() {
  export PARENT_PATH="$REPO_ROOT"
  export CACHE_DIR="$FIXTURES_DIR"

  source "$PARENT_PATH/lib/common/validation.sh"
  source "$PARENT_PATH/lib/quote/quote.sh"
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
  import_secret_variables() { return 0; }
  run get_quote_option -s 100 -x "not-a-date" PLTR
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid expiry date"* ]]
}

@test "get_quote_option: accepts valid expiry date" {
  import_secret_variables() { return 0; }
  send_etrade_query() { echo "{}"; }
  run get_quote_option -s 100 -x "2026-05-02" PLTR
  [ "$status" -eq 0 ]
}
