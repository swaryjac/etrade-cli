#!/bin/bash

readonly CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/etrade/config.json"
readonly DEFAULT_CACHE_DIR="/dev/shm/.etrade_quotes"
readonly DEFAULT_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/etrade"

function _ensure_config_file() {
  if [ ! -f "${CONFIG_FILE}" ]; then
    mkdir -p "$(dirname "${CONFIG_FILE}")"
    printf '{}' > "${CONFIG_FILE}"
  fi
}

function etrade_api_host() {
  [[ "${ETRADE_ENV:-production}" == "sandbox" ]] && echo "apisb.etrade.com" || echo "api.etrade.com"
}

function get_setting() {
  local key_path="$1"
  local value
  [ -f "${CONFIG_FILE}" ] || return 1
  value=$(jq -r ".${key_path} // empty" "${CONFIG_FILE}" 2>/dev/null)
  [ -n "${value}" ] || return 1
  echo "${value}"
}

function set_setting() {
  local key_path="$1"
  local value="$2"
  _ensure_config_file
  local updated
  updated=$(jq --arg val "${value}" ".${key_path} = \$val" "${CONFIG_FILE}") || return 1
  printf '%s\n' "${updated}" > "${CONFIG_FILE}"
}

function load_settings() {
  CACHE_DIR=$(get_setting "directories.cache_dir") || CACHE_DIR="${DEFAULT_CACHE_DIR}"
  export CACHE_DIR

  DATA_DIR=$(get_setting "directories.data_dir") || DATA_DIR="${DEFAULT_DATA_DIR}"
  export DATA_DIR

  local val
  if val=$(get_setting "calc.min_strike");        then export CALC_MIN_STRIKE="${val}";       fi
  if val=$(get_setting "calc.max_strike");        then export CALC_MAX_STRIKE="${val}";       fi
  if val=$(get_setting "calc.min_spread");        then export CALC_MIN_SPREAD="${val}";       fi
  if val=$(get_setting "calc.bid_pct");           then export CALC_BID_PCT="${val}";          fi
  if val=$(get_setting "quote.num_strikes");      then export QUOTE_NUM_STRIKES="${val}";     fi
  if val=$(get_setting "quote.weeks_out");        then export QUOTE_WEEKS_OUT="${val}";       fi
  if val=$(get_setting "quote.retry_attempts");   then export QUOTE_RETRY_ATTEMPTS="${val}";  fi
}
