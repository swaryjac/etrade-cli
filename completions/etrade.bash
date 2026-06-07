_etrade() {
  local cur prev cword
  cur="${COMP_WORDS[COMP_CWORD]}"
  cword=$COMP_CWORD

  local commands="auth quote calc settings acct"

  if [[ $cword -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$commands -h --help" -- "$cur") )
    return
  fi

  local cmd="${COMP_WORDS[1]}"
  if [[ $cword -eq 2 ]]; then
    local subs=""
    case "$cmd" in
      auth)     subs="setup keys check renew get force revoke" ;;
      quote)    subs="price option batch clear" ;;
      calc)     subs="put call skew diff" ;;
      settings) subs="get set list" ;;
      acct)     subs="list setup port activity balance sync" ;;
    esac
    COMPREPLY=( $(compgen -W "$subs -h --help" -- "$cur") )
    return
  fi

  COMPREPLY=()
}

complete -F _etrade etrade
complete -F _etrade ./etrade
