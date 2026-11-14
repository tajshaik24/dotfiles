# Bash 4.4+ / Readline adapter. Commands are always executed by Bash itself.
[[ $- == *i* && -z ${TCOMP_PROVIDER-} ]] || return
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
  printf 'tcomp: Bash 4.4+ is required (macOS: brew install bash).\n' >&2
  return
fi
[[ ${_TCOMP_BASH_LOADED-} == 1 ]] && return
_TCOMP_BASH_LOADED=1
_tcomp_prompt_anchor() {
  local saved_status=$?
  # Expand once per real prompt; redisplay must not rerun command substitutions.
  [[ $PS1 == '${_tcomp_prompt_text}' ]] || _tcomp_prompt_source=$PS1
  (exit "$saved_status")
  _tcomp_prompt_text=${_tcomp_prompt_source@P}
  if shopt -q promptvars; then
    PS1='${_tcomp_prompt_text}'
  else
    PS1=$_tcomp_prompt_source
  fi
  return "$saved_status"
}
# Preserve the user's prompt hooks, including hooks that replace PS1.
if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a '* ]]; then
  PROMPT_COMMAND+=( _tcomp_prompt_anchor )
else
  PROMPT_COMMAND="${PROMPT_COMMAND-}"$'\n''_tcomp_prompt_anchor'
fi

_tcomp_edit() {
  local snapshot action point updated keymap
  snapshot=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/tcomp.XXXXXXXX") || return
  (umask 077; declare -f > "$snapshot/definitions"; complete -p >> "$snapshot/definitions"; compgen -c > "$snapshot/names")
  local prompt=${_tcomp_prompt_text//$'\001'/}
  prompt=${prompt//$'\002'/}
  TCOMP_PROMPT="$prompt" TCOMP_SHELL_EXE=$BASH TCOMP_PROVIDER=1 command tcomp edit bash "$snapshot" "$READLINE_LINE" "$READLINE_POINT" "$READLINE_POINT"
  if [[ -f $snapshot/result ]]; then
    { IFS= read -r action; IFS= read -r point; IFS= read -r -d '' updated || :; } < "$snapshot/result"
    READLINE_LINE=$updated READLINE_POINT=$point
  else
    action=cancel
  fi
  rm -rf -- "$snapshot"
  case $action in
    execute) action=accept-line ;;
    complete) action=complete ;;
    search) action=reverse-search-history ;;
    escape) if [[ -o vi ]]; then action=vi-movement-mode; else action=redraw-current-line; fi ;;
    eof) action='"\C-d"' ;;
    *) action=redraw-current-line ;;
  esac
  for keymap in emacs-standard vi-insert; do
    bind -m "$keymap" '"\C-x\C-a": '"$action"
  done
}

_tcomp_accept_native() {
  command tcomp remember "$READLINE_LINE"
  bind -m emacs-standard '"\C-x\C-a":accept-line'
  bind -m vi-insert '"\C-x\C-a":accept-line'
}

for _tcomp_map in emacs-standard vi-insert; do
  bind -m "$_tcomp_map" -x '"\C-x\C-r":_tcomp_edit'
  bind -m "$_tcomp_map" -x '"\C-x\C-j":_tcomp_accept_native'
  bind -m "$_tcomp_map" '"\C-m":"\C-x\C-j\C-x\C-a"'
  for ((_tcomp_code=32;_tcomp_code<127;_tcomp_code++)); do
    printf -v _tcomp_key "\\$(printf '%03o' "$_tcomp_code")"
    _tcomp_key=${_tcomp_key//\\/\\\\}
    _tcomp_key=${_tcomp_key//\"/\\\"}
    bind -m "$_tcomp_map" "\"$_tcomp_key\":\"\\C-v$_tcomp_key\\C-x\\C-r\\C-x\\C-a\""
  done
  bind -m "$_tcomp_map" '"\C-x\C-a":redraw-current-line'
done
unset _tcomp_map _tcomp_code _tcomp_key

source <(command tcomp completion bash)
