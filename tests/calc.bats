#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures"

setup() {
  command -v bc &>/dev/null || skip "bc is required but not installed (sudo pacman -S bc)"

  export PARENT_PATH="$REPO_ROOT"
  export CACHE_DIR="$FIXTURES_DIR"

  source "$PARENT_PATH/lib/common/validation.sh"
  source "$PARENT_PATH/lib/quote/quote.sh"
  source "$PARENT_PATH/lib/calc/calc.sh"

  cd "$BATS_TEST_TMPDIR"
}

write_symbols_file() {
  printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/symbols.txt"
}

get_csv_file() {
  ls *.csv 2>/dev/null | head -1
}

# ─── Put tests ────────────────────────────────────────────────────────────────

# Fixture data summary (puts, effective min_spread=0):
#   PLTR: stock=146.45, qualifying strike=141.0, bid=1.65, spread=5.45
#   OKLO: stock=66.70,  qualifying strike=58.0,  bid=0.69, spread=8.70
#   BSX:  stock=64.50,  qualifying strike=63.0,  bid=1.05, spread=1.50
#   CHWY: stock=27.49,  qualifying strike=27.0,  bid=0.37, spread=0.49
#   PLUG: stock=2.77,   no qualifying strike (bids below 1% of strike)
#   FAKE: synthetic,    no qualifying strike (all bids set to $0.01)

@test "calc put: qualifying symbol appears in CSV (PLTR)" {
  write_symbols_file "PLTR"
  calc_available_puts -i "$BATS_TEST_TMPDIR/symbols.txt"
  grep -q "^PLTR," "$(get_csv_file)"
}

@test "calc put: non-qualifying symbol produces header-only CSV (PLUG)" {
  write_symbols_file "PLUG"
  calc_available_puts -i "$BATS_TEST_TMPDIR/symbols.txt"
  [ "$(wc -l < "$(get_csv_file)")" -eq 1 ]
}

@test "calc put: multiple symbols, only qualifying ones appear in CSV" {
  write_symbols_file "PLTR" "PLUG" "OKLO"
  calc_available_puts -i "$BATS_TEST_TMPDIR/symbols.txt"
  local csv="$(get_csv_file)"
  grep -q "^PLTR," "$csv"
  grep -q "^OKLO," "$csv"
  ! grep -q "^PLUG," "$csv"
}

@test "calc put: --spread filter excludes symbols below minimum spread" {
  # PLTR spread=5.45 and OKLO spread=8.70, both below --spread 10
  write_symbols_file "PLTR" "OKLO"
  calc_available_puts --spread 10 -i "$BATS_TEST_TMPDIR/symbols.txt"
  local csv="$(get_csv_file)"
  ! grep -q "^PLTR," "$csv"
  ! grep -q "^OKLO," "$csv"
}

@test "calc put: --min-strike filter excludes stocks priced below minimum" {
  # LUNR stock=27.5 is below --min-strike 50, PLTR stock=146.45 is above
  write_symbols_file "LUNR" "PLTR"
  calc_available_puts --min-strike 50 -i "$BATS_TEST_TMPDIR/symbols.txt"
  local csv="$(get_csv_file)"
  ! grep -q "^LUNR," "$csv"
  grep -q "^PLTR," "$csv"
}

@test "calc put: CSV has correct header" {
  write_symbols_file "PLTR"
  calc_available_puts -i "$BATS_TEST_TMPDIR/symbols.txt"
  head -1 "$(get_csv_file)" | grep -q "^SYMBOL,PRICE,STRIKE,PUT_BID,PCT,SPREAD$"
}

# ─── Settings-based defaults ──────────────────────────────────────────────────

@test "calc put: CALC_MIN_SPREAD setting filters without --spread flag" {
  export CALC_MIN_SPREAD=10
  write_symbols_file "PLTR" "OKLO"
  calc_available_puts -i "$BATS_TEST_TMPDIR/symbols.txt"
  local csv="$(get_csv_file)"
  ! grep -q "^PLTR," "$csv"
  ! grep -q "^OKLO," "$csv"
}

@test "calc put: --spread flag overrides CALC_MIN_SPREAD setting" {
  export CALC_MIN_SPREAD=10
  write_symbols_file "PLTR"
  calc_available_puts --spread 0 -i "$BATS_TEST_TMPDIR/symbols.txt"
  grep -q "^PLTR," "$(get_csv_file)"
}

@test "calc put: CALC_MIN_STRIKE setting filters without --min-strike flag" {
  export CALC_MIN_STRIKE=50
  write_symbols_file "LUNR" "PLTR"
  calc_available_puts -i "$BATS_TEST_TMPDIR/symbols.txt"
  local csv="$(get_csv_file)"
  ! grep -q "^LUNR," "$csv"
  grep -q "^PLTR," "$csv"
}

@test "calc put: --min-strike flag overrides CALC_MIN_STRIKE setting" {
  export CALC_MIN_STRIKE=50
  write_symbols_file "LUNR"
  calc_available_puts --min-strike 0 -i "$BATS_TEST_TMPDIR/symbols.txt"
  grep -q "^LUNR," "$(get_csv_file)"
}

@test "calc put: CALC_BID_PCT setting filters options below threshold" {
  # Highest PLTR put ratio below stock price is 2.40% (strike=146, bid=3.5)
  # bid_pct=0.03 gives threshold 4.38, which exceeds all available bids
  export CALC_BID_PCT=0.03
  write_symbols_file "PLTR"
  calc_available_puts -i "$BATS_TEST_TMPDIR/symbols.txt"
  [ "$(wc -l < "$(get_csv_file)")" -eq 1 ]
}

@test "calc put: default CALC_BID_PCT of 0.01 allows qualifying options" {
  unset CALC_BID_PCT
  write_symbols_file "PLTR"
  calc_available_puts -i "$BATS_TEST_TMPDIR/symbols.txt"
  grep -q "^PLTR," "$(get_csv_file)"
}

# ─── Call tests ───────────────────────────────────────────────────────────────

# Fixture data summary (calls, effective min_spread=0):
#   PLTR: stock=146.45, qualifying strike=152.5, bid=1.52, spread=6.05
#   OKLO: stock=66.70,  qualifying strike=80.0,  bid=0.71, spread=13.30
#   BSX:  stock=64.50,  qualifying strike=66.0,  bid=1.25, spread=1.50
#   CHWY: stock=27.49,  qualifying strike=28.0,  bid=0.40, spread=0.51
#   FAKE: synthetic,    no qualifying strike (all bids set to $0.01)

@test "calc call: qualifying symbol appears in CSV (PLTR)" {
  write_symbols_file "PLTR"
  calc_available_calls -i "$BATS_TEST_TMPDIR/symbols.txt"
  grep -q "^PLTR," "$(get_csv_file)"
}

@test "calc call: non-qualifying symbol produces header-only CSV (FAKE)" {
  write_symbols_file "FAKE"
  calc_available_calls -i "$BATS_TEST_TMPDIR/symbols.txt"
  [ "$(wc -l < "$(get_csv_file)")" -eq 1 ]
}

@test "calc call: multiple symbols, only qualifying ones appear in CSV" {
  write_symbols_file "PLTR" "FAKE" "OKLO"
  calc_available_calls -i "$BATS_TEST_TMPDIR/symbols.txt"
  local csv="$(get_csv_file)"
  grep -q "^PLTR," "$csv"
  grep -q "^OKLO," "$csv"
  ! grep -q "^FAKE," "$csv"
}

@test "calc call: --spread filter excludes symbols below minimum spread" {
  # PLTR spread=6.05 excluded, OKLO spread=13.30 included with --spread 10
  write_symbols_file "PLTR" "OKLO"
  calc_available_calls --spread 10 -i "$BATS_TEST_TMPDIR/symbols.txt"
  local csv="$(get_csv_file)"
  ! grep -q "^PLTR," "$csv"
  grep -q "^OKLO," "$csv"
}

@test "calc call: CSV has correct header" {
  write_symbols_file "PLTR"
  calc_available_calls -i "$BATS_TEST_TMPDIR/symbols.txt"
  head -1 "$(get_csv_file)" | grep -q "^SYMBOL,PRICE,STRIKE,CALL_BID,PCT,SPREAD$"
}

# ─── Skew tests ───────────────────────────────────────────────────────────────

# Fixture data summary (skew = call_spread - put_spread):
#   PLTR: put_spread=5.45, call_spread=6.05 → diff=0.60
#   OKLO: put_spread=8.70, call_spread=13.30 → diff=4.60

get_diff_csv_file() {
  ls diff*.csv 2>/dev/null | head -1
}

@test "calc skew: produces put, call, and diff CSV files" {
  write_symbols_file "PLTR"
  calc_skew -i "$BATS_TEST_TMPDIR/symbols.txt"
  ls onepct_puts*.csv >/dev/null 2>&1
  ls onepct_calls*.csv >/dev/null 2>&1
  ls diff*.csv >/dev/null 2>&1
}

@test "calc skew: diff CSV has correct header" {
  write_symbols_file "PLTR"
  calc_skew -i "$BATS_TEST_TMPDIR/symbols.txt"
  head -1 "$(get_diff_csv_file)" | grep -q "^SYMBOL,Stock Price,Call Spread, Put Spread,Diff$"
}

@test "calc skew: diff CSV contains qualifying symbol (PLTR)" {
  write_symbols_file "PLTR"
  calc_skew -i "$BATS_TEST_TMPDIR/symbols.txt"
  grep -q "^PLTR," "$(get_diff_csv_file)"
}

@test "calc skew: diff CSV omits symbol qualifying for call but not put (FAKE)" {
  # FAKE has no qualifying strikes for either put or call, so it should not appear in diff
  write_symbols_file "FAKE"
  calc_skew -i "$BATS_TEST_TMPDIR/symbols.txt"
  ! grep -q "^FAKE," "$(get_diff_csv_file)"
}

@test "calc skew: --spread option propagates to both put and call" {
  # PLTR put_spread=5.45 and call_spread=6.05 both excluded with --spread 10
  write_symbols_file "PLTR" "OKLO"
  calc_skew --spread 10 -i "$BATS_TEST_TMPDIR/symbols.txt"
  local diff_csv="$(get_diff_csv_file)"
  ! grep -q "^PLTR," "$diff_csv"
  grep -q "^OKLO," "$diff_csv"
}

@test "calc skew: CALC_MIN_STRIKE setting produces diff CSV (filename consistency)" {
  # Bug: calc_skew computed filenames with hardcoded 0 instead of CALC_MIN_STRIKE,
  # so it passed wrong paths to call_and_put_diff and the diff CSV was never created.
  export CALC_MIN_STRIKE=50
  write_symbols_file "PLTR"
  calc_skew -i "$BATS_TEST_TMPDIR/symbols.txt"
  grep -q "^PLTR," "$(get_diff_csv_file)"
}
