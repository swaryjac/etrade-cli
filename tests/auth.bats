#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  command -v keyctl &>/dev/null || skip "keyctl is required but not installed"

  export PARENT_PATH="$REPO_ROOT"

  # Stub set_persistent_value so clear_auth_keys doesn't need settings.sh
  function set_persistent_value() { return 0; }

  source "$PARENT_PATH/lib/auth/authorization_keys.sh"

  # Use a test-specific keyring to avoid touching real credentials
  keyring_name="etrade_test_keyring"

  keyctl clear %:"${keyring_name}" 2>/dev/null || true
}

teardown() {
  keyctl clear %:"${keyring_name}" 2>/dev/null || true
}

# ─── get_volatile_key ─────────────────────────────────────────────────────────

@test "get_volatile_key: returns failure when key does not exist" {
  run get_volatile_key "nonexistent_key"
  [ "$status" -ne 0 ]
}

@test "get_volatile_key: returns the value of an existing key" {
  set_volatile_key "${keyring_name}" "test_key" "test_value"
  run get_volatile_key "test_key"
  [ "$status" -eq 0 ]
  [ "$output" = "test_value" ]
}

# ─── set_volatile_key ─────────────────────────────────────────────────────────

@test "set_volatile_key: stored value is retrievable" {
  set_volatile_key "${keyring_name}" "my_key" "my_value"
  run get_volatile_key "my_key"
  [ "$status" -eq 0 ]
  [ "$output" = "my_value" ]
}

@test "set_volatile_key: overwrites existing key with new value" {
  set_volatile_key "${keyring_name}" "my_key" "original"
  set_volatile_key "${keyring_name}" "my_key" "updated"
  run get_volatile_key "my_key"
  [ "$status" -eq 0 ]
  [ "$output" = "updated" ]
}

# ─── clear_volatile_keyring ───────────────────────────────────────────────────

@test "clear_volatile_keyring: keys in the keyring are no longer retrievable" {
  set_volatile_key "${keyring_name}" "key1" "value1"
  set_volatile_key "${keyring_name}" "key2" "value2"
  clear_volatile_keyring "${keyring_name}"
  run get_volatile_key "key1"
  [ "$status" -ne 0 ]
}

# ─── set_auth_keys ────────────────────────────────────────────────────────────

@test "set_auth_keys: returns failure for malformed response" {
  access_response="not_a_valid_oauth_response"
  run set_auth_keys "${access_response}"
  [ "$status" -ne 0 ]
}

@test "set_auth_keys: stores token for valid oauth response" {
  access_response="oauth_token=mytoken123&oauth_token_secret=mysecret456"
  set_auth_keys "${access_response}"
  run get_volatile_key "${auth_token_keyname}"
  [ "$status" -eq 0 ]
  [ "$output" = "mytoken123" ]
}

@test "set_auth_keys: stores secret for valid oauth response" {
  access_response="oauth_token=mytoken123&oauth_token_secret=mysecret456"
  set_auth_keys "${access_response}"
  run get_volatile_key "${auth_secret_keyname}"
  [ "$status" -eq 0 ]
  [ "$output" = "mysecret456" ]
}

# ─── retrieve_auth_keys ───────────────────────────────────────────────────────

@test "retrieve_auth_keys: returns failure when no keys are stored" {
  run retrieve_auth_keys
  [ "$status" -ne 0 ]
}

@test "retrieve_auth_keys: unsets access_token and access_secret on failure" {
  access_token="stale_token"
  access_secret="stale_secret"
  retrieve_auth_keys || true
  [ -z "${access_token}" ]
  [ -z "${access_secret}" ]
}

@test "retrieve_auth_keys: exports access_token when keys are stored" {
  access_response="oauth_token=mytoken123&oauth_token_secret=mysecret456"
  set_auth_keys "${access_response}"
  retrieve_auth_keys
  [ "${access_token}" = "mytoken123" ]
}

@test "retrieve_auth_keys: exports access_secret when keys are stored" {
  access_response="oauth_token=mytoken123&oauth_token_secret=mysecret456"
  set_auth_keys "${access_response}"
  retrieve_auth_keys
  [ "${access_secret}" = "mysecret456" ]
}

# ─── clear_auth_keys ──────────────────────────────────────────────────────────

@test "clear_auth_keys: auth token is not retrievable after clearing" {
  access_response="oauth_token=mytoken123&oauth_token_secret=mysecret456"
  set_auth_keys "${access_response}"
  clear_auth_keys
  run get_volatile_key "${auth_token_keyname}"
  [ "$status" -ne 0 ]
}

@test "clear_auth_keys: retrieve_auth_keys fails after clearing" {
  access_response="oauth_token=mytoken123&oauth_token_secret=mysecret456"
  set_auth_keys "${access_response}"
  clear_auth_keys
  run retrieve_auth_keys
  [ "$status" -ne 0 ]
}
