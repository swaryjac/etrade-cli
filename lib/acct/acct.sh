#!/bin/bash

# Build a human-friendly display name from an account's description/nickname.
# Falls back to the account id only when both are empty.
function _account_display_name() {
  local desc="$1" name="$2" acct_id="$3"
  if [[ -n "${desc}" && -n "${name}" && "${name}" != "${desc}" ]]; then
    printf '%s-%s' "${desc}" "${name}"
  elif [[ -n "${desc}" ]]; then
    printf '%s' "${desc}"
  elif [[ -n "${name}" ]]; then
    printf '%s' "${name}"
  else
    printf '%s' "${acct_id}"
  fi
}

# Print stored accounts as a numbered table. The leading number is the account's
# 1-based position in the stored list and is the identifier accepted by the
# 'port', 'activity' and 'balance' subcommands.
function _print_accounts_table() {
  local accounts_file="$1"
  local num
  num=$(jq '.AccountListResponse.Accounts.Account | length' "${accounts_file}")

  local -a names=() types=() ids=() trackeds=()
  local name_width=7  # length of the "Account" header
  local idx desc name acct_id atype tracked display
  for ((idx = 0; idx < num; idx++)); do
    desc=$(jq -r ".AccountListResponse.Accounts.Account[$idx].accountDesc // \"\"" "${accounts_file}")
    name=$(jq -r ".AccountListResponse.Accounts.Account[$idx].accountName // \"\"" "${accounts_file}")
    acct_id=$(jq -r ".AccountListResponse.Accounts.Account[$idx].accountId  // \"\"" "${accounts_file}")
    atype=$(jq -r ".AccountListResponse.Accounts.Account[$idx].accountType  // \"\"" "${accounts_file}")
    tracked=$(jq -r ".AccountListResponse.Accounts.Account[$idx].tracked    // false" "${accounts_file}")
    display=$(_account_display_name "${desc}" "${name}" "${acct_id}")

    names+=("${display}")
    types+=("${atype}")
    ids+=("${acct_id}")
    if [[ "${tracked}" == "true" ]]; then trackeds+=("yes"); else trackeds+=("no"); fi
    (( ${#display} > name_width )) && name_width=${#display}
  done

  printf "%3s  %-${name_width}s  %-10s  %-12s  %s\n" "#" "Account" "Type" "AccountId" "Tracked"
  local i
  for ((i = 0; i < num; i++)); do
    printf "%3s  %-${name_width}s  %-10s  %-12s  %s\n" \
      "$((i + 1))" "${names[$i]}" "${types[$i]}" "${ids[$i]}" "${trackeds[$i]}"
  done
}

# Resolve a user-supplied account selector to an accountIdKey, using the stored
# accounts.json written by 'setup'. Prints the accountIdKey on success; prints a
# diagnostic to stderr and returns non-zero on failure. Resolution order:
#   1. a 1-based number, as shown by 'acct list -r'
#   2. an exact accountId or accountIdKey
#   3. a unique case-insensitive substring of an account's description/nickname
function _resolve_account_idkey() {
  local selector="$1"
  local accounts_file="${DATA_DIR}/accounts.json"

  if [[ ! -f "${accounts_file}" ]]; then
    printf "No stored account data at %s. Run 'etrade acct setup' first.\n" \
           "${accounts_file}" >&2
    return 1
  fi

  local num
  num=$(jq '.AccountListResponse.Accounts.Account | length' "${accounts_file}")

  # 1. positional number (in range). A numeric selector outside 1..num is not an
  #    error here: account ids are also numeric, so fall through to the exact match.
  if [[ "${selector}" =~ ^[0-9]+$ ]] && (( selector >= 1 && selector <= num )); then
    jq -r ".AccountListResponse.Accounts.Account[$((selector - 1))].accountIdKey" "${accounts_file}"
    return 0
  fi

  # 2. exact accountId or accountIdKey
  local exact
  exact=$(jq -r --arg s "${selector}" '
    .AccountListResponse.Accounts.Account[]
    | select(.accountId == $s or .accountIdKey == $s)
    | .accountIdKey' "${accounts_file}" | head -n1)
  if [[ -n "${exact}" ]]; then
    printf '%s\n' "${exact}"
    return 0
  fi

  # 3. unique case-insensitive name substring
  local lowered matches count
  lowered=$(printf '%s' "${selector}" | tr '[:upper:]' '[:lower:]')
  matches=$(jq -r --arg s "${lowered}" '
    .AccountListResponse.Accounts.Account[]
    | select(
        ((.accountDesc // "") | ascii_downcase | contains($s)) or
        ((.accountName // "") | ascii_downcase | contains($s))
      )
    | .accountIdKey' "${accounts_file}")
  count=$(printf '%s\n' "${matches}" | grep -c .)

  if [[ "${count}" -eq 1 ]]; then
    printf '%s\n' "${matches}"
    return 0
  elif [[ "${count}" -gt 1 ]]; then
    printf "Selector '%s' matches %s accounts; use a number or be more specific.\n" \
           "${selector}" "${count}" >&2
    return 1
  fi

  if [[ "${selector}" =~ ^[0-9]+$ ]]; then
    printf "No account matches '%s' (valid numbers are 1-%s, or use an accountId).\n" \
           "${selector}" "${num}" >&2
  else
    printf "No account matches '%s'. Run 'etrade acct list -r' to see identifiers.\n" \
           "${selector}" >&2
  fi
  return 1
}

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
    _print_accounts_table "${accounts_file}"
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
    local idkey acct_id desc name atype status prior_tracked display
    idkey=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountIdKey"        "${response_file}")
    acct_id=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountId"         "${response_file}")
    desc=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountDesc   // \"\"" "${response_file}")
    name=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountName   // \"\"" "${response_file}")
    atype=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountType  // \"\"" "${response_file}")
    status=$(jq -r ".AccountListResponse.Accounts.Account[$i].accountStatus // \"\"" "${response_file}")
    prior_tracked=$(echo "${prior_map}" | jq -r --arg k "${idkey}" '.[$k] // false')

    display=$(_account_display_name "${desc}" "${name}" "${acct_id}")

    if [[ "${status}" == "CLOSED" ]]; then
      printf "Skipping closed account %s (%s)\n\n" "${display}" "${atype}"
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

    printf "Account %s (%s)\n" "${display}" "${atype}"
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
  local selector="$1"
  if [[ -z "${selector}" ]]; then
    printf "Error: account selector required\n\n" >&2
    usage_acct >&2
    return 1
  fi
  local acct_idkey
  if ! acct_idkey=$(_resolve_account_idkey "${selector}"); then
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
  local selector="$1"
  if [[ -z "${selector}" ]]; then
    printf "Error: account selector required\n\n" >&2
    usage_acct >&2
    return 1
  fi
  local acct_idkey
  if ! acct_idkey=$(_resolve_account_idkey "${selector}"); then
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
  printf "\tetrade acct [port | activity] <account>\n\n"
  local subcmd_len=26
  printf "Subcommands:\n"
  printf "\t%-${subcmd_len}s - %s\n" "list"                       "Fetch account list from the API and print raw JSON"
  printf "\t%-${subcmd_len}s - %s\n" "setup"                      "Fetch accounts and interactively choose which to track for performance"
  printf "\t%-${subcmd_len}s - %s\n" "port <account>"             "Print the portfolio for the given account"
  printf "\t%-${subcmd_len}s - %s\n" "activity <account>"         "Print recent transactions for the given account"
  printf "\n<account> is the number from 'acct list -r', or an accountId/name/accountIdKey.\n"
  printf "\nOptions for 'list':\n"
  printf "\t%-${subcmd_len}s - %s\n" "-r --read-cache"            "Print stored accounts as a numbered table from data_dir (no API call)"
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
