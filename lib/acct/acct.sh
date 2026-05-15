#!/bin/bash

function list_accounts() {
  local OPTS
  OPTS=$(getopt -o r --long read-cache -- "$@")
  if [[ $? != 0 ]]; then
    usage_acct >&2
    return 1
  fi
  eval set -- "$OPTS"
  local read_from_cache=false
  while true; do
    case "$1" in
      -r|--read-cache) read_from_cache=true; shift ;;
      --) shift; break ;;
      *) echo "Option Parsing Error" >&2; return 1 ;;
    esac
  done

  local accounts_file="${DATA_DIR}/accounts.json"

  if $read_from_cache; then
    if [[ ! -f "${accounts_file}" ]]; then
      printf "No stored account data at %s. Run 'etrade acct setup' first.\n" \
             "${accounts_file}" >&2
      return 1
    fi
    cat "${accounts_file}"
    return
  fi

  if ! import_secret_variables; then
    return 1
  fi

  local list_url="https://$(etrade_api_host)/v1/accounts/list.json"

  declare -A acct_params
  acct_params["oauth_token"]="${access_token}"

  send_etrade_query "${list_url}" acct_params "${decoded_access_secret}"
}

function setup_accounts() {
  if ! import_secret_variables; then
    return 1
  fi

  local accounts_file="${DATA_DIR}/accounts.json"
  local response_file
  response_file=$(mktemp)

  local list_url="https://$(etrade_api_host)/v1/accounts/list.json"
  declare -A acct_params
  acct_params["oauth_token"]="${access_token}"

  if ! send_etrade_query "${list_url}" acct_params "${decoded_access_secret}" "${response_file}"; then
    printf "Error: failed to retrieve account list\n" >&2
    rm -f "${response_file}"
    return 1
  fi

  local prior_map="{}"
  if [[ -f "${accounts_file}" ]]; then
    prior_map=$(jq '
      .AccountListResponse.Accounts.Account
      | map({(.accountIdKey): (.tracked // false)})
      | add // {}
    ' "${accounts_file}")
  fi

  local num_accounts
  num_accounts=$(jq '.AccountListResponse.Accounts.Account | length' "${response_file}")
  if [[ -z "${num_accounts}" || "${num_accounts}" == "0" || "${num_accounts}" == "null" ]]; then
    printf "Error: no accounts returned from API\n" >&2
    rm -f "${response_file}"
    return 1
  fi

  printf "Found %d account(s). For each, choose whether to track for performance.\n\n" "${num_accounts}"

  local tracked_map="{"
  local first=true
  local i
  for ((i = 0; i < num_accounts; i++)); do
    local idkey acct_id desc atype status prior_tracked
    idkey=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountIdKey"        "${response_file}")
    acct_id=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountId"          "${response_file}")
    desc=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountDesc   // \"\"" "${response_file}")
    atype=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountType  // \"\"" "${response_file}")
    status=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountStatus // \"\"" "${response_file}")
    prior_tracked=$(echo "${prior_map}" | jq -r --arg k "${idkey}" '.[$k] // false')

    if [[ "${status}" == "CLOSED" ]]; then
      printf "Skipping closed account %s (%s)\n\n" "${acct_id}" "${desc}"
      $first || tracked_map+=","
      tracked_map+="\"${idkey}\":false"
      first=false
      continue
    fi

    local prompt
    if [[ "${prior_tracked}" == "true" ]]; then
      prompt="[Y/n]"
    else
      prompt="[y/N]"
    fi

    printf "Account %s  (%s, %s)\n" "${acct_id}" "${atype}" "${status}"
    [[ -n "${desc}" ]] && printf "  %s\n" "${desc}"
    printf "  Track this account? %s " "${prompt}"

    local answer
    if ! read -r answer < /dev/tty; then
      printf "\nError: cannot read interactive input (no controlling tty); aborting setup\n" >&2
      rm -f "${response_file}"
      return 1
    fi

    local tracked
    if [[ -z "${answer}" ]]; then
      tracked="${prior_tracked}"
    elif [[ "${answer}" =~ ^[Yy] ]]; then
      tracked="true"
    else
      tracked="false"
    fi

    $first || tracked_map+=","
    tracked_map+="\"${idkey}\":${tracked}"
    first=false

    printf "\n"
  done
  tracked_map+="}"

  mkdir -p "${DATA_DIR}"
  jq --argjson trackedMap "${tracked_map}" '
    .AccountListResponse.Accounts.Account |= map(. + {tracked: ($trackedMap[.accountIdKey] // false)})
  ' "${response_file}" > "${accounts_file}"

  rm -f "${response_file}"
  printf "Saved %d account(s) to %s\n" "${num_accounts}" "${accounts_file}"
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
  printf "\tetrade acct list [-r --read-cache]\n"
  printf "\tetrade acct setup\n"
  printf "\tetrade acct [port | activity] <account_id_key>\n\n"
  local subcmd_len=26
  printf "Subcommands:\n"
  printf "\t%-${subcmd_len}s - %s\n" "list"                       "Fetch account list from the API and print raw JSON"
  printf "\t%-${subcmd_len}s - %s\n" "setup"                      "Fetch accounts and interactively choose which to track for performance"
  printf "\t%-${subcmd_len}s - %s\n" "port <account_id_key>"      "Print the portfolio for the given account"
  printf "\t%-${subcmd_len}s - %s\n" "activity <account_id_key>"  "Print recent transactions for the given account"
  printf "\nOptions for 'list':\n"
  printf "\t%-${subcmd_len}s - %s\n" "-r --read-cache"            "Read previously stored account data from data_dir instead of the API"
}

function help_acct() {
  printf "Etrade CLI Acct\n"
  printf "\tRetrieve account details from Etrade. Use 'setup' to choose which accounts to\n"
  printf "\ttrack for performance; the selections are persisted under directories.data_dir.\n"
  printf "\tUse 'list' as a raw-JSON sanity check against the API or stored data.\n\n"
  usage_acct
}

function execute_acct() {
  local subcommand=$1
  case "$subcommand" in
    list)
      shift
      list_accounts "$@"
      ;;
    setup)
      shift
      setup_accounts "$@"
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
