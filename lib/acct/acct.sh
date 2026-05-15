#!/bin/bash

function list_accounts() {
  if ! import_secret_variables; then
    return 1
  fi

  local list_url="https://$(etrade_api_host)/v1/accounts/list.json"

  declare -A acct_params
  acct_params["oauth_token"]="${access_token}"

  send_etrade_query "${list_url}" acct_params "${decoded_access_secret}"
}

function print_portfolio() {
  local acct_idkey="$1"
  if [[ -z "${acct_idkey}" ]]; then
    printf "Error: account id key required\n\n" >&2
    usage_acct >&2
    return 1
  fi
  if ! import_secret_variables; then
    return 1
  fi

  local portfolio_url="https://$(etrade_api_host)/v1/accounts/${acct_idkey}/portfolio.json"

  declare -A portfolio_params
  portfolio_params["oauth_token"]="${access_token}"

  send_etrade_query "${portfolio_url}" portfolio_params "${decoded_access_secret}"
}

function print_activity() {
  local acct_idkey="$1"
  if [[ -z "${acct_idkey}" ]]; then
    printf "Error: account id key required\n\n" >&2
    usage_acct >&2
    return 1
  fi
  if ! import_secret_variables; then
    return 1
  fi

  local activity_url="https://$(etrade_api_host)/v1/accounts/${acct_idkey}/transactions.json"

  declare -A activity_params
  activity_params["oauth_token"]="${access_token}"

  send_etrade_query "${activity_url}" activity_params "${decoded_access_secret}"
}

function usage_acct() {
  printf "Usage:\n"
  printf "\tetrade acct {-h --help}\n"
  printf "\tetrade acct list\n"
  printf "\tetrade acct [port | activity] <account_id_key>\n\n"
  local subcmd_len=26
  printf "Subcommands:\n"
  printf "\t%-${subcmd_len}s - %s\n" "list"                       "List the accounts available for the authorized user"
  printf "\t%-${subcmd_len}s - %s\n" "port <account_id_key>"      "Print the portfolio for the given account"
  printf "\t%-${subcmd_len}s - %s\n" "activity <account_id_key>"  "Print recent transactions for the given account"
}

function help_acct() {
  printf "Etrade CLI Acct\n"
  printf "\tRetrieve account details from Etrade. Use 'list' to find the accountIdKey for each\n"
  printf "\tauthorized account, then pass that key to 'port' or 'activity'.\n\n"
  usage_acct
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
      print_activity "$@"
      ;;
    -h|--help)
      help_acct
      ;;
    *)
      printf "Unrecognized subcommand '%s'\n\n" "${subcommand}" >&2
      usage_acct >&2
      return 1
      ;;
  esac
}
