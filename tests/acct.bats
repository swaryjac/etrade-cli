#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures/acct"

setup() {
  export PARENT_PATH="$REPO_ROOT"
  export DATA_DIR="$BATS_TEST_TMPDIR/data"
  mkdir -p "$DATA_DIR"

  source "$PARENT_PATH/lib/common/config.sh"
  source "$PARENT_PATH/lib/common/http_defns.sh"
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

@test "list -r: prints a header, a rule, and one row per account" {
  run list_accounts -r
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"Account"*"Type"*"AccountId"*"Tracked"* ]]
  # header rule made of dashes
  [[ "${lines[1]}" == "-"*"-" ]]
  [[ "${lines[1]}" != *[![:space:]-]* ]]
  # header + rule + 4 accounts in the sandbox fixture
  [ "${#lines[@]}" -eq 6 ]
}

@test "list -r: numbers accounts by 1-based position" {
  run list_accounts -r
  [[ "${lines[2]}" == "1  "* ]]
  [[ "${lines[3]}" == "2  "* ]]
}

@test "list -r: row carries the account name and accountId" {
  run list_accounts -r
  [[ "${lines[3]}" == *"Complete Savings"* ]]
  [[ "${lines[3]}" == *"583156360"* ]]
}

@test "list -r: tracked column reflects the stored flag" {
  run list_accounts -r
  [[ "${lines[2]}" == *"yes" ]]   # first (active) account
  [[ "${lines[5]}" == *"no" ]]    # last (closed) account
}

@test "list -r: columns stay aligned when a type is wider than its header" {
  # accountType IRA_ROLLOVER (12 chars) exceeds the 'Type' header width; the
  # AccountId column must still start at the same offset on every row.
  cat > "$DATA_DIR/accounts.json" <<'JSON'
{"AccountListResponse":{"Accounts":{"Account":[
  {"accountDesc":"Alpha","accountId":"111111111","accountType":"IRA_ROLLOVER","tracked":true},
  {"accountDesc":"Beta","accountId":"222222222","accountType":"ROTHIRA","tracked":false}
]}}}
JSON
  run list_accounts -r
  [ "$status" -eq 0 ]
  local off1 off2
  off1=$(awk '/111111111/{print index($0,"111111111")}' <<<"$output")
  off2=$(awk '/222222222/{print index($0,"222222222")}' <<<"$output")
  [ "$off1" = "$off2" ]
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

# ─── sync (fetch + Python ingest integration) ───────────────────────────────────

@test "sync: fetches transactions and persists them to the journal" {
  mock_auth_success
  send_etrade_query() { cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  run sync_account 1
  [ "$status" -eq 0 ]

  local base="$DATA_DIR/transactions/dBZOKt9xDrtRSAOl4MSiiA"
  [ -f "$base.jsonl" ]
  [ "$(grep -c . "$base.jsonl")" -eq 7 ]
  run jq -r '.record_count' "$base.meta.json"
  [ "$output" -eq 7 ]
}

@test "sync: re-running does not duplicate records" {
  mock_auth_success
  send_etrade_query() { cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  sync_account 1
  run sync_account 1
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$DATA_DIR/transactions/dBZOKt9xDrtRSAOl4MSiiA.jsonl")" -eq 7 ]
}

@test "sync: first run backfills from two years ago" {
  mock_auth_success
  send_etrade_query() { local -n _p="$2"; echo "${_p[startDate]}" > "$BATS_TEST_TMPDIR/start"
                        cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  run sync_account 1
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/start")" = "$(date -d '2 years ago' +%m%d%Y)" ]
}

@test "sync: subsequent run starts from the newest stored date" {
  mock_auth_success
  send_etrade_query() { local -n _p="$2"; echo "${_p[startDate]}" > "$BATS_TEST_TMPDIR/start"
                        cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  sync_account 1                       # first run populates the watermark
  run sync_account 1                   # second run reads it
  [ "$status" -eq 0 ]
  # newest date in the synthetic fixture is 2026-05-22
  [ "$(cat "$BATS_TEST_TMPDIR/start")" = "$(date -d '2026-05-22' +%m%d%Y)" ]
}

@test "sync: requires an account selector" {
  run sync_account
  [ "$status" -ne 0 ]
}

@test "sync: --since overrides the start date" {
  mock_auth_success
  send_etrade_query() { local -n _p="$2"; echo "${_p[startDate]}" > "$BATS_TEST_TMPDIR/start"
                        echo "${_p[endDate]}" > "$BATS_TEST_TMPDIR/end"
                        cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  run sync_account --since 2026-01-01 1
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/start")" = "01012026" ]
  [ "$(cat "$BATS_TEST_TMPDIR/end")" = "$(date +%m%d%Y)" ]   # default
}

@test "sync: --until bounds the end date" {
  mock_auth_success
  send_etrade_query() { local -n _p="$2"; echo "${_p[endDate]}" > "$BATS_TEST_TMPDIR/end"
                        cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  run sync_account --since 2026-01-01 --until 2026-01-31 1
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/end")" = "01312026" ]
}

@test "sync: --since older than two years is clamped to the floor" {
  mock_auth_success
  send_etrade_query() { local -n _p="$2"; echo "${_p[startDate]}" > "$BATS_TEST_TMPDIR/start"
                        cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  run sync_account --since 2010-01-01 1
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/start")" = "$(date -d '2 years ago' +%m%d%Y)" ]
}

@test "sync: rejects an invalid --since date" {
  mock_auth_success
  send_etrade_query() { cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  run sync_account --since "not-a-date" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --since"* ]]
}

@test "sync: pages backward by date window until a short page" {
  mock_auth_success

  # Page A: a full window of 50 (oldest 2026-04-01). Page B: a short window of 10.
  local pageA="$BATS_TEST_TMPDIR/A.json" pageB="$BATS_TEST_TMPDIR/B.json"
  python3 - "$pageA" "$pageB" <<'PY'
import json, sys
from datetime import datetime
from zoneinfo import ZoneInfo
ET = ZoneInfo("America/New_York")
def ms(y, m, d): return int(datetime(y, m, d, 12, tzinfo=ET).timestamp() * 1000)
def rec(i, epoch): return {"transactionId": f"T{i:04d}", "transactionDate": epoch, "amount": 0,
  "transactionType": "Sold Short", "brokerage": {"product": {"symbol": "ZZZ", "securityType": "OPTN",
  "callPut": "PUT", "expiryYear": 26, "expiryMonth": 5, "expiryDay": 22, "strikePrice": 1},
  "quantity": 1, "price": 0, "fee": 0}}
A = [rec(i, ms(2026, 5, 20) - i * 1000) for i in range(49)] + [rec(49, ms(2026, 4, 1))]
B = [rec(100 + i, ms(2026, 3, 1) - i * 1000) for i in range(10)]
for path, arr in ((sys.argv[1], A), (sys.argv[2], B)):
    json.dump({"TransactionListResponse": {"Transaction": arr}}, open(path, "w"))
PY

  local today; today=$(date +%m%d%Y)
  send_etrade_query() {
    local -n _p="$2"
    if [ "${_p[endDate]}" = "$today" ]; then cp "$pageA" "$4"; else cp "$pageB" "$4"; fi
  }

  export ETRADE_SYNC_DEBUG_DIR="$BATS_TEST_TMPDIR/pages"
  run sync_account 1
  [ "$status" -eq 0 ]

  # exactly two windows fetched: full page A, then short page B stops the loop
  [ -f "$ETRADE_SYNC_DEBUG_DIR/page-0.json" ]
  [ -f "$ETRADE_SYNC_DEBUG_DIR/page-1.json" ]
  [ ! -f "$ETRADE_SYNC_DEBUG_DIR/page-2.json" ]
  # the second window ends at page A's oldest date
  [ "$(cat "$ETRADE_SYNC_DEBUG_DIR/page-1.endDate.txt")" = "$(date -d 2026-04-01 +%m%d%Y)" ]
  # all 60 unique records are stored
  run jq -r '.record_count' "$DATA_DIR/transactions/dBZOKt9xDrtRSAOl4MSiiA.meta.json"
  [ "$output" -eq 60 ]
}

@test "sync: ETRADE_SYNC_DEBUG_DIR captures raw pages" {
  mock_auth_success
  send_etrade_query() { cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  export ETRADE_SYNC_DEBUG_DIR="$BATS_TEST_TMPDIR/pages"
  run sync_account 1
  [ "$status" -eq 0 ]
  [ -f "$ETRADE_SYNC_DEBUG_DIR/page-0.json" ]
  # first window ends today (MMDDYYYY)
  [ "$(cat "$ETRADE_SYNC_DEBUG_DIR/page-0.endDate.txt")" = "$(date +%m%d%Y)" ]
}

# ─── report (journal analytics; no API call) ────────────────────────────────────

@test "report: requires an account selector" {
  run report_account
  [ "$status" -ne 0 ]
}

@test "report: fails cleanly when the account has no journal" {
  run report_account 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no journal"* ]]
}

@test "report: prints weekly put premium CSV from the local journal" {
  mock_auth_success
  send_etrade_query() { cp "$FIXTURES_DIR/transactions_response.json" "$4"; }
  sync_account 1                         # populate the journal first

  run report_account 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"week_ending,contracts,premium,cumulative_premium"* ]]
  # synthetic fixture: one put sold 2026-05-18 -> week ending Fri 2026-05-22
  [[ "$output" == *"2026-05-22,1,48.34,48.34"* ]]
  # the summary reports the put as expired and the unmatched assign as an orphan
  [[ "$output" == *"expired 1"* ]]
  [[ "$output" == *"orphan closes"* ]]
}
