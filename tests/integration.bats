#!/usr/bin/env bats

# Sandbox integration tests. Requires sandbox credentials stored via:
#   etrade auth setup --sandbox
#
# Run:
#   bats tests/integration.bats
#
# If no auth token is present, the test run will prompt for one interactively.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  export PARENT_PATH="$REPO_ROOT"
  export ETRADE_ENV="sandbox"
  export CACHE_DIR="$BATS_TEST_TMPDIR"

  source "$PARENT_PATH/lib/common/config.sh"
  source "$PARENT_PATH/lib/common/http_defns.sh"
  source "$PARENT_PATH/lib/common/validation.sh"
  source "$PARENT_PATH/lib/auth/auth.sh"
  source "$PARENT_PATH/lib/quote/quote.sh"
}

require_sandbox_credentials() {
  if ! load_permanent_api_key 2>/dev/null; then
    skip "No sandbox API key stored (run: etrade auth setup --sandbox)"
  fi
  if ! retrieve_auth_keys 2>/dev/null; then
    has_or_get_authorization || skip "Authorization failed or was cancelled"
  fi
}

# ─── Auth ─────────────────────────────────────────────────────────────────────

@test "auth: sandbox authorization is valid" {
  require_sandbox_credentials
  run is_authorization_valid
  [ "$status" -eq 0 ]
}

# ─── Quote ────────────────────────────────────────────────────────────────────

@test "quote: get_quote returns QuoteResponse for valid symbol" {
  require_sandbox_credentials
  run get_quote AAPL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("QuoteResponse")' > /dev/null
}

@test "quote: get_quote_option returns OptionChainResponse for valid symbol" {
  require_sandbox_credentials
  run get_quote_option AAPL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("OptionChainResponse")' > /dev/null
}

@test "quote: get_quote_batch writes cache file for symbol" {
  require_sandbox_credentials
  echo "AAPL" | get_quote_batch
  [ -f "$(get_quote_filename AAPL)" ]
}
