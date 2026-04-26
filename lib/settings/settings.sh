#!/bin/bash

readonly -a VALID_SETTING_KEYS=(
  "directories.cache_dir"
  "directories.calc_output_dir"
  "calc.min_strike"
  "calc.max_strike"
  "calc.min_spread"
)

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
  local value
  if value=$(get_setting "${key}"); then
    echo "${value}"
  else
    printf "%s is not set\n" "${key}" >&2
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
  local key value
  printf "%-30s %s\n" "KEY" "VALUE"
  printf "%-30s %s\n" "---" "-----"
  for key in "${VALID_SETTING_KEYS[@]}"; do
    if value=$(get_setting "${key}"); then
      printf "%-30s %s\n" "${key}" "${value}"
    else
      printf "%-30s %s\n" "${key}" "(not set)"
    fi
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
