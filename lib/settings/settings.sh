#!/bin/bash

readonly -a VALID_SETTING_KEYS=(
  "directories.cache_dir"
  "directories.calc_output_dir"
  "calc.min_strike"
  "calc.max_strike"
  "calc.min_spread"
  "calc.bid_pct"
  "quote.num_strikes"
  "quote.weeks_out"
  "quote.retry_attempts"
)

function _get_setting_default() {
  case "$1" in
    directories.cache_dir)       echo "${DEFAULT_CACHE_DIR}" ;;
    directories.calc_output_dir) echo "(current directory)" ;;
    calc.min_strike)             echo "0" ;;
    calc.max_strike)             echo "10000" ;;
    calc.min_spread)             echo "0" ;;
    calc.bid_pct)                echo "0.01" ;;
    quote.num_strikes)           echo "40" ;;
    quote.weeks_out)             echo "1" ;;
    quote.retry_attempts)        echo "3" ;;
  esac
}

function _get_setting_note() {
  local key="$1"
  local effective_value="$2"
  case "${key}" in
    quote.weeks_out)
      if [[ "${effective_value}" =~ ^[0-9]+$ ]]; then
        local expiry
        expiry=$(date --date="next friday + $((effective_value - 1)) weeks" +"%Y-%m-%d" 2>/dev/null)
        [ -n "${expiry}" ] && echo "(next expiry: ${expiry})"
      fi
      ;;
  esac
}

function _is_valid_setting_key() {
  local key="$1"
  local valid
  for valid in "${VALID_SETTING_KEYS[@]}"; do
    [ "${key}" = "${valid}" ] && return 0
  done
  return 1
}

function cmd_settings_get() {
  local key="$1"
  if ! _is_valid_setting_key "${key}"; then
    printf "Unknown setting: %s\n" "${key}" >&2
    return 1
  fi
  local value default note
  default="$(_get_setting_default "${key}")"
  if value=$(get_setting "${key}"); then
    note="$(_get_setting_note "${key}" "${value}")"
    [ -n "${note}" ] && echo "${value}  ${note}" || echo "${value}"
  else
    note="$(_get_setting_note "${key}" "${default}")"
    printf "%s is not set (default: %s)%s\n" \
      "${key}" "${default}" "${note:+  ${note}}" >&2
    return 1
  fi
}

function cmd_settings_set() {
  local key="$1"
  local value="$2"
  if ! _is_valid_setting_key "${key}"; then
    printf "Unknown setting: %s\n" "${key}" >&2
    return 1
  fi
  set_setting "${key}" "${value}"
}

function cmd_settings_list() {
  local key value default effective note
  printf "%-30s %-25s %-12s %s\n" "KEY" "VALUE" "DEFAULT" "NOTE"
  printf "%-30s %-25s %-12s %s\n" "---" "-----" "-------" "----"
  for key in "${VALID_SETTING_KEYS[@]}"; do
    default="$(_get_setting_default "${key}")"
    if value=$(get_setting "${key}"); then
      effective="${value}"
    else
      value="(not set)"
      effective="${default}"
    fi
    note="$(_get_setting_note "${key}" "${effective}")"
    printf "%-30s %-25s %-12s %s\n" "${key}" "${value}" "${default}" "${note}"
  done
}

function usage_settings() {
  printf "Usage:\n"
  printf "\tetrade settings {-h --help}\n"
  printf "\tetrade settings <subcommand>\n\n"
  local subcmd_len=20
  printf "Subcommands:\n"
  printf "\t%-${subcmd_len}s - %s\n" "get <key>"         "Print the value of a setting"
  printf "\t%-${subcmd_len}s - %s\n" "set <key> <value>" "Write a setting value"
  printf "\t%-${subcmd_len}s - %s\n" "list"              "List all settings and their values"
  printf "\nValid keys:\n"
  local key
  for key in "${VALID_SETTING_KEYS[@]}"; do
    printf "\t%s\n" "${key}"
  done
}

function help_settings() {
  printf "Etrade CLI Settings\n"
  printf "\tManages persistent configuration stored in %s\n\n" "${CONFIG_FILE}"
  usage_settings
}

function execute_settings() {
  local subcommand="$1"
  shift
  case "${subcommand}" in
    get)
      cmd_settings_get "$1"
      ;;
    set)
      cmd_settings_set "$1" "$2"
      ;;
    list)
      cmd_settings_list
      ;;
    -h|--help)
      help_settings
      ;;
    *)
      printf "Unrecognized subcommand '%s'\n\n" "${subcommand}" >&2
      usage_settings >&2
      return 1
      ;;
  esac
}
