#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  export PARENT_PATH="$REPO_ROOT"

  # Redirect XDG config home so CONFIG_FILE resolves inside the temp dir
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/.config"

  source "$PARENT_PATH/lib/common/settings.sh"
  source "$PARENT_PATH/lib/settings/settings.sh"

  # Pre-create the config directory so tests can write directly to CONFIG_FILE
  mkdir -p "$(dirname "$CONFIG_FILE")"
}

# ─── get_setting ──────────────────────────────────────────────────────────────

@test "get_setting: returns failure when config file does not exist" {
  run get_setting "directories.cache_dir"
  [ "$status" -ne 0 ]
}

@test "get_setting: returns failure for a key not present in config" {
  printf '{}' > "$CONFIG_FILE"
  run get_setting "directories.cache_dir"
  [ "$status" -ne 0 ]
}

@test "get_setting: returns failure for a key explicitly set to null" {
  printf '{"directories":{"cache_dir":null}}' > "$CONFIG_FILE"
  run get_setting "directories.cache_dir"
  [ "$status" -ne 0 ]
}

@test "get_setting: returns value for a key that is set" {
  printf '{"directories":{"cache_dir":"/tmp/quotes"}}' > "$CONFIG_FILE"
  run get_setting "directories.cache_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/quotes" ]
}

# ─── set_setting ──────────────────────────────────────────────────────────────

@test "set_setting: creates config file when it does not exist" {
  set_setting "directories.cache_dir" "/tmp/quotes"
  [ -f "$CONFIG_FILE" ]
}

@test "set_setting: written value is retrievable by get_setting" {
  set_setting "directories.cache_dir" "/tmp/quotes"
  run get_setting "directories.cache_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/quotes" ]
}

@test "set_setting: overwrites existing value" {
  set_setting "directories.cache_dir" "/tmp/original"
  set_setting "directories.cache_dir" "/tmp/updated"
  run get_setting "directories.cache_dir"
  [ "$output" = "/tmp/updated" ]
}

@test "set_setting: sets a key without disturbing other keys" {
  set_setting "directories.cache_dir" "/tmp/quotes"
  set_setting "directories.calc_output_dir" "/tmp/output"
  run get_setting "directories.cache_dir"
  [ "$output" = "/tmp/quotes" ]
}

@test "set_setting: config file remains valid JSON after multiple writes" {
  set_setting "directories.cache_dir" "/tmp/quotes"
  set_setting "calc.min_strike" "100"
  run jq empty "$CONFIG_FILE"
  [ "$status" -eq 0 ]
}

# ─── load_settings ────────────────────────────────────────────────────────────

@test "load_settings: exports default CACHE_DIR when not configured" {
  load_settings
  [ "${CACHE_DIR}" = "${DEFAULT_CACHE_DIR}" ]
}

@test "load_settings: exports configured CACHE_DIR when set" {
  set_setting "directories.cache_dir" "/tmp/custom_quotes"
  load_settings
  [ "${CACHE_DIR}" = "/tmp/custom_quotes" ]
}

@test "load_settings: exports CALC_MIN_STRIKE when configured" {
  set_setting "calc.min_strike" "50"
  load_settings
  [ "${CALC_MIN_STRIKE}" = "50" ]
}

@test "load_settings: exports CALC_MAX_STRIKE when configured" {
  set_setting "calc.max_strike" "200"
  load_settings
  [ "${CALC_MAX_STRIKE}" = "200" ]
}

@test "load_settings: exports CALC_MIN_SPREAD when configured" {
  set_setting "calc.min_spread" "5"
  load_settings
  [ "${CALC_MIN_SPREAD}" = "5" ]
}

@test "load_settings: does not set CALC_MIN_STRIKE when not configured" {
  load_settings
  [ -z "${CALC_MIN_STRIKE}" ]
}

# ─── settings command: get ────────────────────────────────────────────────────

@test "settings get: prints value for a configured key" {
  set_setting "directories.cache_dir" "/tmp/quotes"
  run cmd_settings_get "directories.cache_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/quotes" ]
}

@test "settings get: returns failure and message for unset key" {
  run cmd_settings_get "directories.cache_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not set"* ]]
}

@test "settings get: includes default value in message when key is not set" {
  run cmd_settings_get "directories.cache_dir"
  [[ "$output" == *"${DEFAULT_CACHE_DIR}"* ]]
}

@test "settings get: returns failure for an unknown key" {
  run cmd_settings_get "invalid.key"
  [ "$status" -ne 0 ]
}

# ─── settings command: set ────────────────────────────────────────────────────

@test "settings set: persists value retrievable by get" {
  cmd_settings_set "directories.cache_dir" "/tmp/quotes"
  run cmd_settings_get "directories.cache_dir"
  [ "$output" = "/tmp/quotes" ]
}

@test "settings set: returns failure for an unknown key" {
  run cmd_settings_set "invalid.key" "value"
  [ "$status" -ne 0 ]
}

# ─── settings command: list ───────────────────────────────────────────────────

@test "settings list: includes all valid keys in output" {
  run cmd_settings_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "directories.cache_dir"
  echo "$output" | grep -q "directories.calc_output_dir"
  echo "$output" | grep -q "calc.min_strike"
  echo "$output" | grep -q "calc.max_strike"
  echo "$output" | grep -q "calc.min_spread"
}

@test "settings list: shows configured value for a set key" {
  set_setting "directories.cache_dir" "/tmp/quotes"
  run cmd_settings_list
  echo "$output" | grep -q "/tmp/quotes"
}

@test "settings list: shows not-set marker for unset keys" {
  run cmd_settings_list
  echo "$output" | grep -q "(not set)"
}

@test "settings list: shows default values column" {
  run cmd_settings_list
  echo "$output" | grep -q "DEFAULT"
  echo "$output" | grep -q "${DEFAULT_CACHE_DIR}"
}
