#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures/acct"

setup() {
  export PARENT_PATH="$REPO_ROOT"
  export DATA_DIR="$BATS_TEST_TMPDIR/data"
  mkdir -p "$DATA_DIR"

  source "$PARENT_PATH/lib/common/config.sh"
  source "$PARENT_PATH/lib/acct/acct.sh"
  source "$REPO_ROOT/tests/mocks.sh"

  # Stored accounts.json mirrors what 'setup' persists: the list response with a
  # 'tracked' flag per account (active = tracked, closed = not).
  jq '.AccountListResponse.Accounts.Account |= map(. + {tracked: (.accountStatus != "CLOSED")})' \
    "$FIXTURES_DIR/list_response_sandbox.json" > "$DATA_DIR/accounts.json"
}

# ─── acct list -r (numbered table) ──────────────────────────────────────────────

@test "list -r: fails when no stored accounts file exists" {
  export DATA_DIR="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$DATA_DIR"
  run list_accounts -r
  [ "$status" -ne 0 ]
  [[ "$output" == *"acct setup"* ]]
}

@test "list -r: prints a header and one numbered row per account" {
  run list_accounts -r
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"Account"*"Type"*"AccountId"*"Tracked"* ]]
  # 1 header + 4 accounts in the sandbox fixture
  [ "${#lines[@]}" -eq 5 ]
}

@test "list -r: numbers accounts by 1-based position" {
  run list_accounts -r
  [[ "${lines[1]}" == "  1 "* ]]
  [[ "${lines[2]}" == "  2 "* ]]
}

@test "list -r: row carries the account name and accountId" {
  run list_accounts -r
  [[ "${lines[2]}" == *"Complete Savings"* ]]
  [[ "${lines[2]}" == *"583156360"* ]]
}

@test "list -r: tracked column reflects the stored flag" {
  run list_accounts -r
  [[ "${lines[1]}" == *"yes" ]]   # active account
  [[ "${lines[4]}" == *"no" ]]    # closed account
}

# ─── _resolve_account_idkey ─────────────────────────────────────────────────────

@test "resolve: positional number maps to that account's idkey" {
  run _resolve_account_idkey 2
  [ "$status" -eq 0 ]
  [ "$output" = "vQMsebA1H5WltUfDkJP48g" ]
}

@test "resolve: exact accountId maps to the idkey" {
  run _resolve_account_idkey 707004180
  [ "$status" -eq 0 ]
  [ "$output" = "6_Dpy0rmuQ9cu9IbTfvF2A" ]
}

@test "resolve: literal accountIdKey resolves to itself" {
  run _resolve_account_idkey dBZOKt9xDrtRSAOl4MSiiA
  [ "$status" -eq 0 ]
  [ "$output" = "dBZOKt9xDrtRSAOl4MSiiA" ]
}

@test "resolve: unique case-insensitive name substring resolves" {
  run _resolve_account_idkey savings
  [ "$status" -eq 0 ]
  [ "$output" = "vQMsebA1H5WltUfDkJP48g" ]
}

@test "resolve: ambiguous name substring fails" {
  run _resolve_account_idkey INDIVIDUAL
  [ "$status" -ne 0 ]
  [[ "$output" == *"matches"* ]]
}

@test "resolve: unknown selector fails" {
  run _resolve_account_idkey zzz
  [ "$status" -ne 0 ]
  [[ "$output" == *"No account matches"* ]]
}

@test "resolve: out-of-range number fails with range hint" {
  run _resolve_account_idkey 99
  [ "$status" -ne 0 ]
  [[ "$output" == *"1-4"* ]]
}

@test "resolve: missing accounts file fails" {
  export DATA_DIR="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$DATA_DIR"
  run _resolve_account_idkey 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"acct setup"* ]]
}

# ─── port / activity / balance wiring ───────────────────────────────────────────

@test "activity: resolves selector into the transactions URL" {
  mock_auth_success
  mock_api_captures_url "$FIXTURES_DIR/activity_response_sandbox.json"
  run print_activity 3
  [ "$status" -eq 0 ]
  [[ "$(cat "$_mock_captured_url_file")" == *"/accounts/6_Dpy0rmuQ9cu9IbTfvF2A/transactions.json" ]]
}

@test "port: resolves a name selector into the portfolio URL" {
  mock_auth_success
  mock_api_captures_url "$FIXTURES_DIR/list_response_sandbox.json"
  run print_portfolio savings
  [ "$status" -eq 0 ]
  [[ "$(cat "$_mock_captured_url_file")" == *"/accounts/vQMsebA1H5WltUfDkJP48g/portfolio.json" ]]
}

@test "balance: hits the balance URL with instType in the signed params" {
  mock_auth_success
  # Custom mock: record the URL and the signed parameter array.
  _cap="$BATS_TEST_TMPDIR/cap"
  send_etrade_query() {
    local -n _p="$2"
    printf '%s instType=%s realTimeNAV=%s\n' "$1" "${_p[instType]}" "${_p[realTimeNAV]}" > "$_cap"
  }
  run print_balance 1
  [ "$status" -eq 0 ]
  [[ "$(cat "$_cap")" == *"/accounts/dBZOKt9xDrtRSAOl4MSiiA/balance.json"* ]]
  [[ "$(cat "$_cap")" == *"instType=BROKERAGE"* ]]
  [[ "$(cat "$_cap")" == *"realTimeNAV=true"* ]]
}

@test "port/activity/balance: require an account selector" {
  run print_portfolio
  [ "$status" -ne 0 ]
  run print_activity
  [ "$status" -ne 0 ]
  run print_balance
  [ "$status" -ne 0 ]
}
