#!/bin/bash

accounts_url_base="https://api.etrade.com/v1/accounts"
list_account_url="https://api.etrade.com/v1/accounts/list.json"

function list_accounts() {
  if ! import_secret_variables; then
    return 1
  fi

  declare -A acct_params

  acct_params["oauth_token"]="${access_token}"

  send_etrade_query "${list_account_url}" acct_params "${decoded_access_secret}"
}

function print_portfolio() {
  if ! import_secret_variables; then
    return 1
  fi
  local acct_idkey="$1"

  portfolio_url="${accounts_url_base}/${acct_idkey}/portfolio.json"

  declare -A portfolio_params

  portfolio_params["oauth_token"]="${access_token}"

  send_etrade_query "${portfolio_url}" portfolio_params "${decoded_access_secret}"
}

function activity() {
  if ! import_secret_variables; then
    return 1
  fi
  local acct_idkey="$1"

  activity_url="${accounts_url_base}/${acct_idkey}/transactions.json"

  declare -A activity_params

  activity_params["oauth_token"]="${access_token}"

  send_etrade_query "${activity_url}" activity_params "${decoded_access_secret}"
}

function execute_acct() {
  local subcommand=$1
  case "$subcommand" in
    list)
      shift
      list_accounts "$@"
      ;;
    port)
      shift
      print_portfolio "$@"
      ;;
    activity)
      shift
      activity "$@"
      ;;
    -h|--help)
      help_calc
      ;;
    *)
      printf "Unrecognized subcommand '${subcommand}'\n\n" 1>&2
      usage_calc 1>&2
      ;;
  esac
}