# Sourced by ~/.zshrc after installing tcomp.
if (( ! $+functions[_main_complete] )); then
  autoload -Uz compinit
  compinit -D
fi
zmodload zsh/stat
zmodload zsh/zutil
zmodload zsh/zselect
zmodload zsh/zpty 2>/dev/null
zmodload zsh/system   # $sysparams[pid] for background workers
zmodload zsh/datetime # $EPOCHSECONDS for Ctrl+R history
# Inside widgets fd 0 always polls as readable, so keep our own handle on the
# terminal to notice the next keypress without consuming it.
typeset -g _tcomp_tty=''
# Braces scope the 2>/dev/null: a bare `exec ... 2>/dev/null` would redirect
# the whole shell's stderr to /dev/null for the rest of the session.
[[ -t 0 ]] && { exec {_tcomp_tty}</dev/tty } 2>/dev/null

typeset -gaU _tcomp_hits
typeset -gA _tcomp_option_kinds
typeset -gA _tcomp_branch_candidates
typeset -gA _tcomp_usage
_tcomp_usage=()
typeset -g _tcomp_option_source='' _tcomp_option_stamp=''
typeset -g _tcomp_history_dir=''
typeset -ga _tcomp_history_lines
typeset -gA _tcomp_history_time   # command -> unix time it last ran here (history.tsv 3rd field)
typeset -gi _tcomp_moved=0   # the highlight was moved with the arrow keys
typeset -gi _tcomp_selected=1 _tcomp_pulse=0 _tcomp_injected=0 _tcomp_popular_count=0 _tcomp_stale=0
typeset -gA _tcomp_abbr
typeset -g _tcomp_abbr_file="$HOME/.config/tcomp/abbr.tsv" _tcomp_abbr_stamp=''
typeset -gi _tcomp_hist_mode=0 _tcomp_hist_max=20 _tcomp_search_mode=0

_tcomp_load_usage() {
  local kind context label key weight
  local file="$HOME/.config/tcomp/usage.log"
  [[ -r $file ]] || return
  while IFS=$'\x1f' read -r kind context label; do
    [[ ( $kind == C || $kind == R ) && -n $label ]] || continue
    key="$context"$'\x1f'"$label"
    weight=1
    [[ $kind == C ]] && weight=3
    _tcomp_usage[$key]=$(( ${_tcomp_usage[$key]:-0} + weight ))
  done < "$file"
}
_tcomp_load_usage

_tcomp_record() {
  local kind=$1 context=$2 label=$3 key weight=1
  [[ -n $label && $context != *$'\n'* && $context != *$'\r'* && $context != *$'\x1f'* \
    && $label != *$'\n'* && $label != *$'\r'* && $label != *$'\x1f'* ]] || return
  local file="$HOME/.config/tcomp/usage.log"
  # ponytail: append-only log; compact it if startup parsing becomes slow.
  (umask 077; mkdir -p -- "${file:h}" && printf '%s\x1f%s\x1f%s\n' "$kind" "$context" "$label" >> "$file") || return
  key="$context"$'\x1f'"$label"
  [[ $kind == C ]] && weight=3
  _tcomp_usage[$key]=$(( ${_tcomp_usage[$key]:-0} + weight ))
}

_tcomp_record_line() {
  local line=$1 context='' token
  [[ $line != *$'\n'* ]] || return
  local -a words=( ${(z)line} )
  for token in "${words[@]}"; do
    [[ $token == '|' || $token == ';' || $token == '&&' || $token == '||' ]] && break
    token=${(Q)token}
    _tcomp_record R "$context" "$token"
    context+="${context:+ }$token"
  done
}

_tcomp_history_load_dir() {
  _tcomp_history_dir=$PWD
  _tcomp_history_lines=()
  _tcomp_history_time=()
  local dir line when file="$HOME/.config/tcomp/history.tsv"
  [[ -r $file ]] || return
  # <dir> US <command> [US <unix time>]; older lines have no time.
  while IFS=$'\x1f' read -r dir line when; do
    [[ $dir == $_tcomp_history_dir && -n $line ]] || continue
    _tcomp_history_lines+=( "$line" )
    [[ $when == <-> ]] && _tcomp_history_time[$line]=$when
  done < "$file"
  (( $#_tcomp_history_lines > 1000 )) && _tcomp_history_lines=( "${_tcomp_history_lines[-1000,-1][@]}" )
}

_tcomp_history_record() {
  local line=$1 file="$HOME/.config/tcomp/history.tsv"
  [[ -n $line && $line != *$'\n'* && $line != *$'\r'* && $line != *$'\x1f'* \
    && $PWD != *$'\n'* && $PWD != *$'\r'* && $PWD != *$'\x1f'* ]] || return
  [[ -o hist_ignore_space && $line == ' '* ]] && return
  (umask 077; mkdir -p -- "${file:h}" && touch -- "$file" && chmod 600 "$file" && printf '%s\x1f%s\x1f%s\n' "$PWD" "$line" "$EPOCHSECONDS" >> "$file") || return
  [[ $_tcomp_history_dir == $PWD ]] || _tcomp_history_load_dir
  _tcomp_history_lines+=( "$line" )
  _tcomp_history_time[$line]=$EPOCHSECONDS
  (( $#_tcomp_history_lines > 1000 )) && _tcomp_history_lines=( "${_tcomp_history_lines[-1000,-1][@]}" )
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _tcomp_history_load_dir
_tcomp_history_load_dir

_tcomp_rank_group() {
  local context=$1 record label key score position
  shift
  local -a ranked=() scores=()
  for record in "$@"; do
    label=${record%%$'\t'*}
    key="$context"$'\x1f'"$label"
    score=${_tcomp_usage[$key]:-0}
    if (( score == 0 )); then
      ranked+=( "$record" )
      scores+=( 0 )
      continue
    fi
    position=1
    while (( position <= $#ranked && scores[position] >= score )); do
      (( position++ ))
    done
    if (( position == 1 )); then
      ranked=( "$record" "${ranked[@]}" )
      scores=( "$score" "${scores[@]}" )
    elif (( position > $#ranked )); then
      ranked+=( "$record" )
      scores+=( "$score" )
    else
      ranked=( "${ranked[1,position-1][@]}" "$record" "${ranked[position,-1][@]}" )
      scores=( "${scores[1,position-1][@]}" "$score" "${scores[position,-1][@]}" )
    fi
  done
  reply=( "${ranked[@]}" )
}

_tcomp_compadd() {
  local -a hits descriptions _tcomp_records
  local -A addopts
  local item insert index kind hidden_prefix hidden_suffix file_name description
  for item in "$@"; do
    if [[ $item == -A || $item == -D || $item == -O ]]; then
      builtin compadd "$@"
      return
    fi
  done
  zparseopts -E -A addopts a k q Q f e n U l 1 2 C P: S: p: s: i: I: W: d: J: X: x: V: o:: r: R: D: O: A: E: M: F:
  hidden_prefix=${addopts[-p]-}
  hidden_suffix=${addopts[-s]-}
  if (( ! ${+addopts[-Q]} )); then
    [[ -n $hidden_prefix ]] && hidden_prefix=${(q)hidden_prefix}
    [[ -n $hidden_suffix ]] && hidden_suffix=${(q)hidden_suffix}
  fi
  # Display strings (e.g. "--all  -- do not ignore entries") arrive via -d; -D keeps them aligned with hits.
  [[ -n ${addopts[-d]-} ]] && descriptions=( "${(@P)addopts[-d]}" )
  builtin compadd -A hits -D descriptions "$@"
  for (( index = 1; index <= $#hits; index++ )); do
    # -A quotes the match body, but omits compadd's surrounding insertion fields.
    insert=$hits[index]
    item=${(Q)insert}
    [[ -n $item && $item != *$'\n'* && $item != *$'\t'* ]] || continue
    file_name=${(Q)${addopts[-W]-$hidden_prefix}}$item
    if (( ${+addopts[-f]} )) && [[ -d $file_name && $insert != */ && -z $hidden_suffix ]]; then
      insert+='/'
    fi
    insert="${addopts[-i]-}${addopts[-P]-}$hidden_prefix$insert$hidden_suffix${addopts[-S]-}${addopts[-I]-}"
    (( ${+addopts[-U]} )) || insert="$IPREFIX$insert$ISUFFIX"
    if [[ ${curtag-} == *branch* || ${curtag-} == heads* || ${curtag-} == *-heads* ]]; then
      _tcomp_branch_candidates[$item]=1
    fi
    if [[ -n ${_tcomp_option_kinds[$item]-} ]]; then
      kind=${_tcomp_option_kinds[$item]}
    elif [[ $item == --?* ]]; then
      kind=option
    elif [[ $item == -* ]]; then
      kind=flag
    elif [[ $curcontext == *:-command-:* ]]; then
      kind=command
    elif [[ ${_type-} == *command* ]] || { (( CURRENT == 2 )) && [[ $curcontext == *:argument-1 ]]; }; then
      kind=subcommand
    else
      kind=argument
    fi
    description=${descriptions[index]-}
    if [[ $description == *' -- '* ]]; then
      description=${description#* -- }
    elif [[ ${description//[[:space:]]/} == ${item//[[:space:]]/} ]]; then
      description=''
    fi
    _tcomp_records+=( "$item"$'\t'"$insert"$'\t'"${description//$'\n'/ }"$'\t'"$kind" )
  done
  # Deduplicate once per batch instead of rescanning the unique array for each hit.
  _tcomp_hits+=( "${_tcomp_records[@]}" )
  builtin compadd "$@"
}

_tcomp_capture() {
  _tcomp_hits=()
  _tcomp_branch_candidates=()
  typeset -g _tcomp_start=$(( CURSOR - ${#PREFIX} ))
  local previous=${functions[compadd]-} had_previous=$+functions[compadd]
  functions[compadd]=$functions[_tcomp_compadd]
  # Ungrouped option lists give each flag its own "-x -- description" display string.
  local -a grouped_style
  zstyle -g grouped_style ':completion:*' list-grouped
  zstyle ':completion:*' list-grouped false
  {
    # Candidates arrive through compadd; provider diagnostics must not redraw ZLE.
    _main_complete >/dev/null 2>&1
  } always {
    if (( $#grouped_style )); then
      zstyle ':completion:*' list-grouped "${grouped_style[@]}"
    else
      zstyle -d ':completion:*' list-grouped
    fi
    if (( had_previous )); then
      functions[compadd]=$previous
    else
      unfunction compadd
    fi
  }
  compstate[insert]=''
  compstate[list]=''
}
zle -C _tcomp_capture complete-word _tcomp_capture

_tcomp_render() {
  region_highlight=(${region_highlight:#*memo=tcomp})
  POSTDISPLAY=''
  (( $#_tcomp_hits )) || { _tcomp_abbr_hint; return }
  # History lists (Up menu, Ctrl+R) show more rows than completion menus.
  local rows=5
  (( _tcomp_search_mode )) && rows=8
  _tcomp_in_hist && rows=8
  local first=$(( _tcomp_selected > rows ? _tcomp_selected - rows + 1 : 1 ))
  # History lists (Up menu and Ctrl+R): their own look (header, selection bar,
  # ages, key hints).
  local -i hist_view=0 shown hist_width label_width
  { (( _tcomp_search_mode )) || _tcomp_in_hist } && hist_view=1
  if (( hist_view )); then
    # On an empty line any other plugin's highlights would land on the menu.
    [[ -z $BUFFER ]] && region_highlight=()
    (( hist_width = COLUMNS - 1 < 72 ? COLUMNS - 1 : 72 ))
    (( label_width = hist_width - 7 > 1 ? hist_width - 7 : 1 ))
    _tcomp_hist_header $hist_width
  fi
  local index description row start kind icon color rest record label icon_offset label_offset width range
  local -i popular
  rest=${_tcomp_hits[_tcomp_selected]#*$'\t'}
  rest=${rest#*$'\t'}
  description=${rest%%$'\t'*}
  for (( index = first; index <= $#_tcomp_hits && index < first + rows; index++ )); do
    record=${_tcomp_hits[index]}
    label=${record%%$'\t'*}
    kind=${record##*$'\t'}
    [[ -n $label ]] || continue
    case $kind in
      history) icon='◷'; color=8 ;;
      command) icon='⌘'; color=cyan ;;
      subcommand) icon='↳'; color=magenta ;;
      argument) icon='●'; color=green ;;
      option) icon='◇'; color=blue ;;
      flag) icon='⚑'; color=yellow ;;
    esac
    # Your most-picked items here (up to 3, ranked first) get a ★ after the name.
    (( popular = index <= _tcomp_popular_count ))
    POSTDISPLAY+=$'\n'
    start=$(( ${#BUFFER} + ${#POSTDISPLAY} ))
    if (( hist_view )); then
      _tcomp_hist_row $index $start $label_width "$label" "${${record#*$'\t'*$'\t'}%%$'\t'*}"
      continue
    fi
    icon_offset=2
    label_offset=4
    width=41
    if (( index == _tcomp_selected && _tcomp_pulse )); then
      icon_offset=3
      label_offset=7
      width=38
    elif (( _tcomp_pulse && (index == _tcomp_selected - 1 || index == _tcomp_selected + 1) )); then
      label_offset=5
      width=40
    fi
    (( width = COLUMNS - label_offset - 1 < width ? COLUMNS - label_offset - 1 : width ))
    (( width < 0 )) && width=0
    # History rows show the whole command (wrapping if needed), never a cut-off prefix.
    [[ $kind == history ]] && (( ${#label} > width )) && width=${#label}
    if (( index == _tcomp_selected && _tcomp_pulse )); then
      printf -v row ' ➜ %s   %-*.*s' "$icon" $width $width "$label"
    elif (( index == _tcomp_selected )); then
      printf -v row '→ %s %-*.*s' "$icon" $width $width "$label"
    elif (( _tcomp_pulse && (index == _tcomp_selected - 1 || index == _tcomp_selected + 1) )); then
      printf -v row '  %s  %-*.*s' "$icon" $width $width "$label"
    else
      printf -v row '  %s %-*.*s' "$icon" $width $width "$label"
    fi
    if (( popular && ${#label} + 2 <= width )); then
      local -i star=$(( label_offset + ${#label} + 2 ))
      row[star]='★'
      region_highlight+=( "$((start + label_offset + ${#label} + 1)) $((start + label_offset + ${#label} + 2)) fg=yellow memo=tcomp" )
    fi
    POSTDISPLAY+=$row
    if (( index == _tcomp_selected )); then
      if (( _tcomp_pulse )); then
        region_highlight+=( "$((start + 1)) $((start + 2)) fg=cyan,bold memo=tcomp" )
      else
        region_highlight+=( "$start $((start + 1)) fg=cyan,bold memo=tcomp" )
      fi
    fi
    region_highlight+=( "$((start + icon_offset)) $((start + icon_offset + 1)) fg=$color memo=tcomp" )
    if (( index == _tcomp_selected || (_tcomp_pulse && (index == _tcomp_selected - 1 || index == _tcomp_selected + 1)) )); then
      local label_style=bold
      (( index == _tcomp_selected )) && label_style=fg=cyan,bold
      region_highlight+=( "$((start + label_offset)) $((start + label_offset + (${#label} < width ? ${#label} : width))) $label_style memo=tcomp" )
    fi
  done
  if (( hist_view )); then
    _tcomp_hist_footer
    return
  fi
  POSTDISPLAY+=$'\n'
  width=$(( COLUMNS > 2 ? COLUMNS - 2 : 0 ))
  (( width > 44 )) && width=44
  printf -v row ' %-*.*s' $width $width "$description"
  POSTDISPLAY+=$row
  _tcomp_abbr_hint
}

_tcomp_complete() {
  # Kept on screen while a background completion runs (minus the history row,
  # which is recomputed), so the menu doesn't blank out for ~100ms.
  local -a previous_hits=( "${(@)_tcomp_hits:#*$'\t'history}" )
  POSTDISPLAY=''
  region_highlight=(${region_highlight:#*memo=tcomp})
  _tcomp_hits=()
  _tcomp_branch_candidates=()
  _tcomp_popular_count=0
  _tcomp_injected=0
  [[ -n $BUFFER && $BUFFER != *$'\n'* ]] || return

  _tcomp_async_cancel
  local original_buffer=$BUFFER original_cursor=$CURSOR record label
  if ! _tcomp_cache_filter; then
    # Slow completers (git runs ~13 git commands) go to a background worker so
    # typing never waits; the menu appears when _tcomp_async_ready gets results.
    if _tcomp_should_async && _tcomp_async_start; then
      _tcomp_hits=( "${previous_hits[@]}" )
      return
    fi
    _tcomp_gather
    _tcomp_cache_save
  fi
  (( $#_tcomp_hits )) || return
  _tcomp_rank_hits
}

# ------------------------------------------------------- per-word candidate cache
# Completing a word asks zsh (and often git, brew, ...) for every candidate, which
# can take 100ms+. Typing more letters of the same word can only narrow that
# list, so filter the list we already have instead of asking again.
typeset -g _tcomp_cache_buffer=''
typeset -gi _tcomp_cache_start=0
typeset -ga _tcomp_cache_hits

_tcomp_cache_save() {
  _tcomp_cache_buffer=''
  (( $#_tcomp_hits && ! _tcomp_injected && original_cursor == ${#original_buffer} )) || return
  local typed=${original_buffer[$((_tcomp_start + 1)),-1]} record
  # An empty word can list less than its first letter does (`git push o` adds
  # more than `git push ` had), so only cache once a letter is typed.
  [[ -n $typed ]] || return
  # Only cache lists where every candidate literally starts with the typed text;
  # path components and fuzzy matcher results don't, and must be recomputed.
  for record in "${_tcomp_hits[@]}"; do
    [[ ${record%%$'\t'*} == "$typed"* ]] || return
  done
  _tcomp_cache_buffer=$original_buffer
  _tcomp_cache_start=$_tcomp_start
  _tcomp_cache_hits=( "${_tcomp_hits[@]}" )
}

# Succeeds (filling _tcomp_hits) when BUFFER is the cached line plus more
# plain word characters typed at the end.
_tcomp_cache_filter() {
  [[ -n $_tcomp_cache_buffer && $CURSOR == ${#BUFFER} ]] || return 1
  # A bare command name with completions (`git`, `cd`) shows its subcommands or
  # arguments, not commands named git*, so that needs a real completion.
  if [[ $BUFFER != *' '* ]] && { (( $+commands[$BUFFER] )) || [[ -n ${_comps[$BUFFER]-} ]] }; then
    return 1
  fi
  [[ ${BUFFER[1,${#_tcomp_cache_buffer}]} == "$_tcomp_cache_buffer" ]] || return 1
  [[ ${BUFFER[$(( ${#_tcomp_cache_buffer} + 1 )),-1]} != *[^A-Za-z0-9._+@-]* ]] || return 1
  local typed=${BUFFER[$((_tcomp_cache_start + 1)),-1]} record
  # Options aren't a narrowing: `ls ` lists files, `ls -` flags, `--` long options.
  [[ $typed != [-+]* ]] || return 1
  for record in "${_tcomp_cache_hits[@]}"; do
    [[ ${record%%$'\t'*} == "$typed"* ]] && _tcomp_hits+=( "$record" )
  done
  _tcomp_start=$_tcomp_cache_start
  return 0
}

# ------------------------------------------------------- background completion
# A worker is a fork of this shell (zpty), so it has the same directory,
# environment and completion setup. It runs _tcomp_gather on the request line,
# prints the results between markers and exits. A newer request cancels it;
# the parent reads results when its pty becomes readable (zle -F), so the
# line editor never blocks on it.
typeset -g _tcomp_worker_fd='' _tcomp_worker_buffer='' _tcomp_worker_out=''
typeset -gi _tcomp_worker_cursor=0
typeset -g _tcomp_mark_start=$'\0TCOMP<\0' _tcomp_mark_end=$'\0TCOMP>\0'

# Typing and Tab-accepting opt in (local _tcomp_async_ok=1); other callers need
# the menu immediately. Starting a worker blocks ~3-6ms, about what a fast
# completion costs anyway, so there's no need to guess which ones are slow.
_tcomp_should_async() {
  (( ${_tcomp_async_ok:-0} && $+modules[zsh/zpty] )) || return 1
  # `~name` needs the user list, which zsh loads lazily from macOS's directory
  # service, and that fails in a forked process. Doing it here loads it once
  # (~12ms) in this shell, where later workers inherit it. `~/` is just $HOME.
  local word=${${BUFFER[1,CURSOR]}##*[[:space:]]}
  [[ $word != '~' && $word != \~[^/]* ]]
}

_tcomp_async_start() {
  _tcomp_worker_out=''
  _tcomp_worker_buffer=$BUFFER
  _tcomp_worker_cursor=$CURSOR
  zpty -b _tcomp_worker "_tcomp_worker_main ${(q)BUFFER} $CURSOR" 2>/dev/null || return 1
  _tcomp_worker_fd=$REPLY
  zle -F -w $_tcomp_worker_fd _tcomp_async_ready
}

_tcomp_async_cancel() {
  [[ -n $_tcomp_worker_fd ]] || return 0
  zle -F $_tcomp_worker_fd 2>/dev/null
  zpty -d _tcomp_worker 2>/dev/null
  _tcomp_worker_fd=''
}

# Collect whatever the worker has written; true once the end marker is in.
_tcomp_async_read() {
  local chunk
  while zpty -rt _tcomp_worker chunk 2>/dev/null; do
    _tcomp_worker_out+=$chunk
  done
  [[ $_tcomp_worker_out == *$_tcomp_mark_end* ]]
}

# Block (up to ~3s: 150 polls of 20ms) for the running worker; for keys that
# act on the menu. A dead worker polls readable at once, so it gives up fast.
_tcomp_async_wait() {
  local -i polls=150
  until _tcomp_async_read; do
    (( polls-- > 0 )) || return 1
    zselect -t 2 -r $_tcomp_worker_fd 2>/dev/null
  done
}

# Install the finished worker's results as the menu for the current line.
_tcomp_async_apply() {
  local payload=${${_tcomp_worker_out#*$_tcomp_mark_start}%%$_tcomp_mark_end*}
  _tcomp_async_cancel
  local -a fields=( "${(@0)payload}" )
  local original_buffer=$BUFFER original_cursor=$CURSOR
  _tcomp_start=${fields[1]:-$CURSOR}
  _tcomp_injected=${fields[2]:-0}
  _tcomp_hits=( "${(@)fields[3,-1]:#}" )
  _tcomp_popular_count=0
  _tcomp_stale=0
  _tcomp_cache_save
  (( $#_tcomp_hits )) && _tcomp_rank_hits
  _tcomp_preview_finish
}

_tcomp_async_ready() {
  local fd=$1 condition=${2-}
  [[ $fd == $_tcomp_worker_fd ]] || { zle -F $fd 2>/dev/null; return }
  (( _tcomp_search_mode )) && { _tcomp_async_cancel; return }
  if ! _tcomp_async_read; then
    [[ -n $condition ]] && _tcomp_async_cancel   # worker died without answering
    return
  fi
  # Discard answers for a line that has since changed.
  if [[ $BUFFER != $_tcomp_worker_buffer || $CURSOR != $_tcomp_worker_cursor ]]; then
    _tcomp_async_cancel
    return
  fi
  _tcomp_async_apply
  zle -R
}
zle -N _tcomp_async_ready

# --- worker side (runs inside the zpty fork) ---
# The fork happens inside a widget, so the worker is still "in" the line
# editor with the same BUFFER and can run the completion widget directly.
_tcomp_worker_main() {
  unset HISTFILE
  BUFFER=$1 CURSOR=$2
  _tcomp_gather 2>/dev/null
  print -rn -- "$_tcomp_mark_start$_tcomp_start"$'\0'"$_tcomp_injected"$'\0'"${(pj:\0:)_tcomp_hits}$_tcomp_mark_end"
  # SIGKILL skips exit-time cleanup, which could otherwise reset the real terminal.
  kill -KILL $sysparams[pid]
}

_tcomp_gather() {
  local original_buffer=$BUFFER original_cursor=$CURSOR command_name=${BUFFER%% *} record label
  local option_file="$HOME/.config/tcomp/options/$command_name.tsv" stamp=''
  local -A file_stat
  if [[ $command_name != */* ]] && zstat -H file_stat "$option_file" 2>/dev/null; then
    stamp="${file_stat[ino]}:${file_stat[mtime]}"
  fi
  if [[ $command_name != $_tcomp_option_source || $stamp != $_tcomp_option_stamp ]]; then
    _tcomp_option_kinds=()
    if [[ -n $stamp && -r $option_file ]]; then
      local option_name option_kind
      while IFS=$'\t' read -r option_name option_kind; do
        [[ $option_name == -* && ( $option_kind == option || $option_kind == flag ) ]] || continue
        _tcomp_option_kinds[$option_name]=$option_kind
      done < "$option_file"
    fi
    _tcomp_option_source=$command_name
    _tcomp_option_stamp=$stamp
  fi
  if (( $+commands[$command_name] )) && [[ -z ${_comps[$command_name]-} ]] && [[ $command_name != *[^a-zA-Z0-9_.+-]* ]]; then
    local completion_dir
    for completion_dir in "${fpath[@]}"; do
      if [[ -r "$completion_dir/_$command_name" ]]; then
        autoload -Uz "_$command_name"
        compdef "_$command_name" "$command_name"
        break
      fi
    done
    if [[ -z ${_comps[$command_name]-} && -r "$HOME/.config/tcomp/generated/$command_name.zsh" ]]; then
      source "$HOME/.config/tcomp/generated/$command_name.zsh" >/dev/null 2>&1
    fi
  fi
  if (( $+commands[$command_name] )) && [[ -z ${_comps[$command_name]-} ]]; then
    local remainder=${original_buffer#$command_name} fallback="$HOME/.config/tcomp/fallback/$command_name.tsv"
    [[ $original_cursor == ${#original_buffer} && ( -z $remainder || $remainder == ' '* ) ]] || return
    remainder=${remainder#' '}
    local typed=${remainder##*' '}
    typeset -g _tcomp_start=$(( original_cursor - ${#typed} ))
    [[ $original_buffer == $command_name ]] && _tcomp_injected=1
    local external='' item kind description
    if (( $+commands[tcomp] )); then
      local completion_line=$original_buffer
      (( _tcomp_injected )) && completion_line+=' '
      external=$(command tcomp external "$command_name" "$completion_line" 2>/dev/null)
    fi
    local -a external_lines=( ${(f)external} )
    if [[ ${external_lines[1]-} == provider ]]; then
      for record in "${external_lines[@]:1}"; do
        item=${record%%$'\t'*}
        description=${record#*$'\t'}
        [[ $record == *$'\t'* ]] || description=''
        [[ -n $item && $item == "$typed"* ]] || continue
        if [[ $item == --* ]]; then kind=option
        elif [[ $item == -* ]]; then kind=flag
        elif [[ $remainder != *' '* ]]; then kind=subcommand
        else kind=argument
        fi
        _tcomp_hits+=( "$item"$'\t'"${(q)item}"$'\t'"$description"$'\t'"$kind" )
      done
    elif [[ ${external_lines[1]-} == cache ]]; then
      for record in "${external_lines[@]:1}"; do
        item=${record%%$'\t'*}
        kind=${record#*$'\t'}
        [[ -n $item && $item == "$typed"* && ( $kind == subcommand || $kind == option || $kind == flag ) ]] || continue
        _tcomp_hits+=( "$item"$'\t'"${(q)item}"$'\t'$'\t'"$kind" )
      done
    else
      [[ $remainder != *' '* ]] || return
      [[ -r $fallback ]] || return
      while IFS=$'\t' read -r item kind; do
        [[ -n $item && $item == "$remainder"* && ( $kind == subcommand || $kind == option || $kind == flag ) ]] || continue
        _tcomp_hits+=( "$item"$'\t'"${(q)item}"$'\t'$'\t'"$kind" )
      done < "$fallback"
    fi
  else
    if [[ $BUFFER == $command_name && $CURSOR == ${#BUFFER} && -n ${_comps[$command_name]-} ]]; then
      BUFFER+=' '
      CURSOR=${#BUFFER}
      _tcomp_injected=1
    fi
    zle _tcomp_capture
    BUFFER=$original_buffer
    CURSOR=$original_cursor
  fi

  if (( $#_tcomp_branch_candidates )); then
    local -a branch_hits
    for record in "${_tcomp_hits[@]}"; do
      label=${record%%$'\t'*}
      [[ $label == -* || -n ${_tcomp_branch_candidates[$label]-} ]] && branch_hits+=( "$record" )
    done
    _tcomp_hits=( "${branch_hits[@]}" )
  fi
}

# Orders _tcomp_hits by usage (uses the caller's original_buffer/original_cursor).
_tcomp_rank_hits() {
  local -a subcommands flags
  local record label typed_prefix=${original_buffer[$((_tcomp_start + 1)),$original_cursor]}
  for record in "${_tcomp_hits[@]}"; do
    label=${record%%$'\t'*}
    if [[ $typed_prefix == --* && $typed_prefix != *=* ]]; then
      [[ $label == --* ]] || continue
    elif [[ $typed_prefix == -* && $typed_prefix != *=* ]]; then
      [[ $label == -* && $label != --* ]] || continue
    fi
    if [[ $label == -* ]]; then
      flags+=( "$record" )
    else
      subcommands+=( "$record" )
    fi
  done
  local context=${original_buffer[1,_tcomp_start]} key
  local -a context_words=( ${(z)context} )
  context="${(j: :)context_words}"
  _tcomp_rank_group "$context" "${subcommands[@]}" "${flags[@]}"
  _tcomp_hits=( "${reply[@]}" )
  (( $#_tcomp_hits )) || return
  for record in "${_tcomp_hits[@]}"; do
    label=${record%%$'\t'*}
    key="$context"$'\x1f'"$label"
    (( ${_tcomp_usage[$key]:-0} > 0 )) || break
    (( ++_tcomp_popular_count == 3 )) && break
  done
  (( _tcomp_selected > $#_tcomp_hits )) && _tcomp_selected=$#_tcomp_hits
}

_tcomp_preview() {
  _tcomp_stale=0
  if (( _tcomp_search_mode )); then
    # Ctrl+R: the line is the search query. Nothing matching: back to completions.
    _tcomp_search_fill && { _tcomp_render; return }
    _tcomp_search_mode=0
  fi
  _tcomp_complete
  _tcomp_preview_finish
}

# Draw; also run when background results land. No history row while typing:
# history lives in the Up menu and Ctrl+R.
_tcomp_preview_finish() {
  (( _tcomp_selected > $#_tcomp_hits )) && _tcomp_selected=$#_tcomp_hits
  (( _tcomp_selected < 1 )) && _tcomp_selected=1
  _tcomp_render
}

_tcomp_after_edit() {
  zle ".$WIDGET" "$@"
  _tcomp_selected=1
  _tcomp_pulse=0
  _tcomp_moved=0
  # More keys already queued (fast typing or a paste): skip this refresh, since
  # each one can take 100ms+ and the keys behind it would lag.
  if (( PENDING )); then
    _tcomp_async_cancel
    _tcomp_hits=(); POSTDISPLAY=''
    region_highlight=(${region_highlight:#*memo=tcomp})
    _tcomp_stale=1
    return
  fi
  local _tcomp_async_ok=1
  _tcomp_preview
  zle -R
}

# True if a key is already queued, or one arrives within $1 centiseconds.
_tcomp_key_waiting() {
  (( PENDING )) && return 0
  (( $1 > 0 )) && [[ -n $_tcomp_tty ]] || return 1
  zselect -t $1 -r $_tcomp_tty 2>/dev/null
}

# Before acting on the menu, make it current: wait for a background result
# for this exact line, or rebuild it if typing skipped the last refresh.
_tcomp_refresh_stale() {
  if [[ -n $_tcomp_worker_fd ]]; then
    if [[ $BUFFER == $_tcomp_worker_buffer && $CURSOR == $_tcomp_worker_cursor ]] && _tcomp_async_wait; then
      _tcomp_async_apply
      return 0
    fi
    _tcomp_async_cancel
    _tcomp_stale=1
  fi
  (( _tcomp_stale )) || return 0
  _tcomp_selected=1
  _tcomp_preview
}
for _tcomp_widget in self-insert backward-delete-char delete-char backward-kill-word kill-word kill-whole-line bracketed-paste backward-char beginning-of-line; do
  zle -N "$_tcomp_widget" _tcomp_after_edit
done
unset _tcomp_widget

_tcomp_redraw_move() {
  local previous=$1
  (( previous != _tcomp_selected )) && _tcomp_moved=1
  if (( $#_tcomp_hits )); then
    # Pulse only when no key is waiting, and cut it short when one arrives,
    # so holding Up/Down keeps pace with key repeat instead of queueing.
    # History lists (Up menu, Ctrl+R) move the arrow in place: no pulse.
    if (( previous != _tcomp_selected && ! PENDING && ! _tcomp_search_mode )) && ! _tcomp_in_hist; then
      _tcomp_pulse=1
      _tcomp_render
      zle -R
      _tcomp_key_waiting 6
      _tcomp_pulse=0
    fi
    _tcomp_render
  else
    _tcomp_preview
  fi
  zle -R
}

_tcomp_up() {
  _tcomp_refresh_stale
  local previous=$_tcomp_selected
  if _tcomp_in_hist; then
    # History menu lists newest first: Up moves the highlight up, toward newer;
    # Up on the newest row closes the menu.
    if (( _tcomp_selected == 1 )); then
      _tcomp_hist_close
      zle -R
      return
    fi
    (( _tcomp_selected-- ))
  elif [[ -z $BUFFER ]] && (( ! $#_tcomp_hits )) && _tcomp_hist_open; then
    _tcomp_render
    zle -R
    return
  elif (( $#_tcomp_hits )); then
    (( _tcomp_selected = _tcomp_selected > 1 ? _tcomp_selected - 1 : 1 ))
  else
    zle up-line-or-history
    _tcomp_selected=1
  fi
  _tcomp_redraw_move $previous
}

_tcomp_down() {
  _tcomp_refresh_stale
  local previous=$_tcomp_selected
  if _tcomp_in_hist; then
    # Down moves the highlight down the list, toward older commands.
    (( _tcomp_selected < $#_tcomp_hits )) && (( _tcomp_selected++ ))
  elif (( $#_tcomp_hits )); then
    (( _tcomp_selected = _tcomp_selected < $#_tcomp_hits ? _tcomp_selected + 1 : $#_tcomp_hits ))
  else
    zle down-line-or-history
    _tcomp_selected=1
  fi
  _tcomp_redraw_move $previous
}

_tcomp_choose() {
  _tcomp_hist_mode=0
  _tcomp_refresh_stale
  _tcomp_search_mode=0
  local _tcomp_async_ok=1   # the menu for the line after accepting can load in the background
  if (( CURSOR < ${#BUFFER} )); then
    zle forward-char
    return
  fi
  if (( ! $#_tcomp_hits )); then
    zle forward-char
    return
  fi
  local -a previous_hits=( "${_tcomp_hits[@]}" )
  local record=${_tcomp_hits[_tcomp_selected]}
  local label=${record%%$'\t'*}
  local rest=${record#*$'\t'} insert
  insert=${rest%%$'\t'*}
  if [[ ${record##*$'\t'} == history ]]; then
    BUFFER=$insert
    CURSOR=${#BUFFER}
    _tcomp_selected=1
    _tcomp_preview
    zle -R
    return
  fi
  local prefix=${BUFFER[1,_tcomp_start]} suffix=${BUFFER[$(( CURSOR + 1 )),-1]}
  local -a context_words=( ${(z)prefix} )
  local context="${(j: :)context_words}"
  (( _tcomp_injected )) && prefix+=' '
  local space=' '
  [[ -n $suffix || $insert == */ ]] && space=''
  BUFFER="$prefix$insert$space$suffix"
  CURSOR=$(( ${#prefix} + ${#insert} + ${#space} ))
  _tcomp_record C "$context" "$label"
  _tcomp_selected=1
  _tcomp_preview
  local index same=1
  if [[ -n $_tcomp_worker_fd ]]; then
    same=0   # still loading in the background; it will redraw
  elif (( $#_tcomp_hits != $#previous_hits )); then
    same=0
  else
    for (( index = 1; index <= $#_tcomp_hits; index++ )); do
      [[ ${_tcomp_hits[index]} == ${previous_hits[index]} ]] || { same=0; break; }
    done
  fi
  if (( same )); then
    _tcomp_hits=()
    _tcomp_render
  fi
  zle -R
}

_tcomp_end_of_line() {
  zle .end-of-line
  _tcomp_preview
  zle -R
}

# Enter uses the highlighted completion only when you moved to it with the
# arrows; otherwise the line runs exactly as typed (so `ls ␣` + Enter is `ls`).
_tcomp_enter_takes_highlight() {
  (( CURSOR == ${#BUFFER} )) || return 1
  (( _tcomp_moved )) || return 1
  _tcomp_refresh_stale
  (( $#_tcomp_hits && _tcomp_selected >= 1 && _tcomp_selected <= $#_tcomp_hits ))
}

_tcomp_accept_line() {
  if (( _tcomp_search_mode )); then
    # Enter in Ctrl+R puts the command on the line; a second Enter runs it.
    _tcomp_refresh_stale
    if (( _tcomp_search_mode && $#_tcomp_hits )); then
      _tcomp_choose
      return
    fi
  fi
  if (( ! _tcomp_search_mode )) && ! _tcomp_in_hist && _tcomp_enter_takes_highlight; then
    # Completion menu: put the highlighted item on the line, then run it below.
    local record=${_tcomp_hits[_tcomp_selected]} rest insert prefix
    rest=${record#*$'\t'}; insert=${rest%%$'\t'*}
    if [[ ${record##*$'\t'} == history ]]; then
      BUFFER=$insert
    else
      prefix=${BUFFER[1,_tcomp_start]}
      (( _tcomp_injected )) && prefix+=' '
      local -a context_words=( ${(z)prefix} )
      _tcomp_record C "${(j: :)context_words}" "${record%%$'\t'*}"
      BUFFER=$prefix$insert
    fi
    CURSOR=${#BUFFER}
  fi
  if _tcomp_in_hist; then
    # Enter in the history menu runs the highlighted command, like Up + Enter.
    local record=${_tcomp_hits[_tcomp_selected]}
    BUFFER=${${record#*$'\t'}%%$'\t'*}
    CURSOR=${#BUFFER}
  elif ! _tcomp_abbr_expand_line; then
    # An expansion left a %| spot to fill in (e.g. a commit message): edit, don't run.
    _tcomp_selected=1
    _tcomp_hits=(); POSTDISPLAY=''
    region_highlight=(${region_highlight:#*memo=tcomp})
    (( CURSOR == ${#BUFFER} )) && _tcomp_preview
    zle -R
    return
  fi
  _tcomp_hist_mode=0
  _tcomp_search_mode=0
  _tcomp_async_cancel
  _tcomp_history_record "$BUFFER"
  _tcomp_record_line "$BUFFER"
  POSTDISPLAY=''
  region_highlight=(${region_highlight:#*memo=tcomp})
  _tcomp_hits=()
  zle -R
  zle .accept-line
}

zle -N _tcomp_up
zle -N _tcomp_down
zle -N _tcomp_choose
zle -N _tcomp_end_of_line
zle -N _tcomp_accept_line

# ---------------------------------------------------------------- abbreviations
# ~/.config/tcomp/abbr.tsv: <abbreviation><TAB><expansion>; %| marks the cursor.


_tcomp_abbr_load() {
  local -A st; local key value stamp=''
  zstat -H st "$_tcomp_abbr_file" 2>/dev/null && stamp="${st[ino]}:${st[mtime]}"
  [[ $stamp == $_tcomp_abbr_stamp ]] && return   # reload only when the file changes
  _tcomp_abbr_stamp=$stamp
  _tcomp_abbr=()
  [[ -r $_tcomp_abbr_file ]] || return
  while IFS=$'\t' read -r key value; do
    [[ -n $key && -n $value && $key != \#* ]] || continue
    _tcomp_abbr[$key]=$value
  done < "$_tcomp_abbr_file"
}

# Sets REPLY to the abbreviation that ends at the cursor (longest wins).
# It must start the line or follow ; | & so `echo gc` is left alone.
_tcomp_abbr_match() {
  REPLY=''
  (( CURSOR == ${#BUFFER} )) || return 1
  _tcomp_abbr_load
  local key before
  for key in ${(O@)${(k)_tcomp_abbr}}; do
    [[ $BUFFER == *"$key" ]] || continue
    before=${BUFFER%"$key"}
    [[ -z $before || $before =~ '[;|&][[:space:]]*$' ]] || continue
    (( ${#key} > ${#REPLY} )) && REPLY=$key
  done
  [[ -n $REPLY ]]
}

_tcomp_abbr_expand() {
  local key=$1 value=${_tcomp_abbr[$1]} before=${BUFFER%"$1"} mark='%|'
  if [[ $value == *"$mark"* ]]; then
    BUFFER="$before${value/"$mark"/}"
    CURSOR=$(( ${#before} + ${#${value%%"$mark"*}} ))
  else
    BUFFER="$before$value "
    CURSOR=${#BUFFER}
  fi
  _tcomp_selected=1
  _tcomp_hits=(); POSTDISPLAY=''
  region_highlight=(${region_highlight:#*memo=tcomp})
  # Only refresh the menu when the cursor is at the end (tcomp's menus need that).
  (( CURSOR == ${#BUFFER} )) && _tcomp_preview
  zle -R
}

# Enter: expand every abbreviation in command position (line start, or after
# ; | &), so `ll src` runs `ls -GplAh src` the way an alias would.
# A %| expansion with nothing after it stops for editing (returns 1);
# with arguments after it, a trailing %| is dropped and a mid-line one
# (gc -m "%|") is skipped in favour of a shorter abbreviation (gc).
_tcomp_abbr_expand_line() {
  emulate -L zsh
  setopt extended_glob
  _tcomp_abbr_load
  (( $#_tcomp_abbr )) || return 0
  local mark='%|' word prefix key best value after
  local -a starts
  local -i pos=1 command=1 start index cursor=-1 has_args
  # Offsets of command words, found by walking zsh's own tokenization.
  for word in "${(z)BUFFER}"; do
    case $word in
      ($'\n'|';'|'&&'|'||'|'|'|'|&'|'&'|'&!'|'&|') command=1; continue ;;
    esac
    prefix=${BUFFER[pos,-1]%%${(b)word}*}
    (( pos += ${#prefix} ))
    (( command )) && starts+=( $pos )
    (( pos += ${#word} ))
    command=0
  done
  # Right to left, so earlier offsets stay valid.
  for (( index = $#starts; index >= 1; index-- )); do
    start=$starts[index]
    best=''
    for key in ${(k)_tcomp_abbr}; do
      (( ${#key} > ${#best} )) || continue
      [[ ${BUFFER[start,start+${#key}-1]} == "$key" ]] || continue
      after=${BUFFER[start+${#key},-1]}
      [[ -z $after || $after == [[:space:]\;\|\&]* ]] || continue
      value=${_tcomp_abbr[$key]}
      if [[ $value == *"$mark"?* && $after != [[:space:]]#(|[\;\|\&]*) ]]; then
        continue
      fi
      best=$key
    done
    [[ -n $best ]] || continue
    value=${_tcomp_abbr[$best]}
    after=${BUFFER[start+${#best},-1]}
    has_args=0
    [[ $after == [[:space:]]#(|[\;\|\&]*) ]] || has_args=1
    (( cursor >= 0 )) && (( cursor += ${#${value/"$mark"/}} - ${#best} ))
    if [[ $value == *"$mark"* ]]; then
      if (( has_args )); then
        value=${${value/"$mark"/}%%[[:space:]]#}
      else
        cursor=$(( start - 1 + ${#${value%%"$mark"*}} ))
        value=${value/"$mark"/}
      fi
    fi
    BUFFER=${BUFFER[1,start-1]}$value$after
  done
  (( cursor < 0 )) && return 0
  CURSOR=$cursor
  return 1
}

# Yellow "⇥ expansion" line under the prompt whenever Tab would expand an abbreviation.
_tcomp_abbr_hint() {
  (( _tcomp_search_mode )) && return
  _tcomp_in_hist && return
  _tcomp_abbr_match || return
  local mark='%|' hint start
  hint="  ⇥ ${${_tcomp_abbr[$REPLY]}/"$mark"/}"
  start=$(( ${#BUFFER} + ${#POSTDISPLAY} + 1 ))
  POSTDISPLAY+=$'
'"$hint"
  region_highlight+=( "$start $(( start + ${#hint} )) fg=yellow memo=tcomp" )
}

# ---------------------------------------------------------------- history menu

# "  ◷ history · ~/dir                     3/20", or for Ctrl+R
# "  ⌕ search · every session              3/120"
_tcomp_hist_header() {
  local -i width=$1 start
  local title='◷ history' dir=${(D)PWD} pos="$_tcomp_selected/$#_tcomp_hits" row
  (( _tcomp_search_mode )) && { title='⌕ search'; dir='every session' }
  local -i room=$(( width - 2 - ${#title} - 3 - ${#pos} - 1 ))
  (( ${#dir} > room && room > 1 )) && dir="…${dir[-(room - 1),-1]}"
  (( room < 1 )) && dir=''
  printf -v row '  %s · %-*s %s' "$title" $(( width - 2 - ${#title} - 3 - ${#pos} - 1 )) "$dir" "$pos"
  start=$(( ${#BUFFER} + ${#POSTDISPLAY} + 1 ))
  POSTDISPLAY+=$'\n'$row
  region_highlight+=(
    "$((start + 2)) $((start + 2 + ${#title})) fg=blue,bold memo=tcomp"
    "$((start + 2 + ${#title})) $((start + ${#row})) fg=8 memo=tcomp"
  )
}

# One history row: selection bar, command name in colour, age on the right,
# Ctrl+R matches in yellow. Long commands are cut with … unless selected,
# which shows in full. $5 is the row's description: "@<time>" from Ctrl+R.
_tcomp_hist_row() {
  local -i index=$1 start=$2 width=$3 shown end age_start
  local label=$4 text row marker='  ' age_color=8 range
  local -i t=${_tcomp_history_time[$label]:-0} r=${_tcomp_ran_time[$label]:-0}
  (( r > t )) && t=r
  [[ $5 == @<-> ]] && (( ${5#@} > t )) && t=${5#@}
  _tcomp_short_ago $t
  (( t && EPOCHSECONDS - t < 3600 )) && age_color=green
  (( t && EPOCHSECONDS - t >= 3600 && EPOCHSECONDS - t < 86400 )) && age_color=yellow
  text=$label
  if (( index == _tcomp_selected )); then
    marker='→ '
    (( shown = ${#label} > width ? ${#label} : width ))
  else
    (( ${#text} > width )) && text="${text[1,width-1]}…"
    shown=$width
  fi
  printf -v row '%s%-*s  %3s ' "$marker" $shown "$text" "$REPLY"
  POSTDISPLAY+=$row
  end=$(( start + ${#row} ))
  age_start=$(( start + 2 + shown + 2 ))
  local word=${text%% *}
  if (( index == _tcomp_selected )); then
    region_highlight+=(
      "$start $end bg=236 memo=tcomp"
      "$start $((start + 1)) fg=cyan,bold,bg=236 memo=tcomp"
      "$((start + 2)) $((start + 2 + ${#text})) fg=white,bold,bg=236 memo=tcomp"
      "$((start + 2)) $((start + 2 + ${#word})) fg=cyan,bold,bg=236 memo=tcomp"
      "$age_start $((age_start + 3)) fg=$age_color,bg=236 memo=tcomp"
    )
  else
    region_highlight+=(
      "$((start + 2)) $((start + 2 + ${#word})) fg=green memo=tcomp"
      "$age_start $((age_start + 3)) fg=$age_color memo=tcomp"
    )
  fi
  if (( _tcomp_search_mode )) && _tcomp_match_ranges "$label"; then
    local bg=''
    (( index == _tcomp_selected )) && bg=',bg=236'
    local -i from to visible=${#text}
    [[ $text == *… ]] && (( visible-- ))
    for range in $reply; do   # after the row styles, so it wins
      from=${range% *}; to=${range#* }
      (( from >= visible )) && continue
      (( to > visible )) && to=visible
      region_highlight+=( "$((start + 2 + from)) $((start + 2 + to)) fg=yellow,bold$bg memo=tcomp" )
    done
  fi
}

_tcomp_hist_footer() {
  local hint='  ↵ run   → edit   ↑↓ move   ^R search   ^G close' start
  (( _tcomp_search_mode )) && hint='  ↵ fill   → edit   ↑↓ move   type to filter   ^R/^G close'
  start=$(( ${#BUFFER} + ${#POSTDISPLAY} + 1 ))
  POSTDISPLAY+=$'\n'$hint
  region_highlight+=( "$start $((start + ${#hint})) fg=8 memo=tcomp" )
}

_tcomp_in_hist() {
  [[ -z $BUFFER ]] && (( _tcomp_hist_mode && $#_tcomp_hits ))
}

_tcomp_hist_open() {
  local line; local -A seen
  _tcomp_ran_load   # run times for the age column
  _tcomp_hits=()
  for line in "${(@Oa)_tcomp_history_lines}"; do        # newest first
    [[ -n $line && -z ${seen[$line]} && $line != *[[:cntrl:]]* ]] || continue
    seen[$line]=1
    _tcomp_hits+=( "$line"$'\t'"$line"$'\tHistory\thistory' )
    (( $#_tcomp_hits >= _tcomp_hist_max )) && break
  done
  (( $#_tcomp_hits )) || return 1
  _tcomp_hist_mode=1
  _tcomp_selected=1
  _tcomp_popular_count=0
}

_tcomp_hist_close() {
  _tcomp_hist_mode=0
  _tcomp_hits=()
  _tcomp_selected=1
  _tcomp_render
}

# Escape-ish: Ctrl+G closes the history menu or Ctrl+R search.
_tcomp_cancel() {
  if (( _tcomp_search_mode )); then _tcomp_search_close
  elif _tcomp_in_hist; then _tcomp_hist_close; zle -R
  else zle send-break; fi
}

# ---------------------------------------------------------------- Ctrl+R search
# ~/.config/tcomp/ran.tsv: <unix time><TAB><command>, one line per command that
# exited 0, from every session. Seeded once from zsh's history (time 0).
# Ctrl+R lists them newest first, each once, filtered by the line: commands
# starting with it, then containing it, then with its letters in order.

typeset -g _tcomp_ran_file="$HOME/.config/tcomp/ran.tsv" _tcomp_ran_stamp='' _tcomp_ran_pending=''
typeset -ga _tcomp_ran          # newest first, unique
typeset -gA _tcomp_ran_time     # command -> unix time of its latest run
typeset -gi _tcomp_ran_max=2000 _tcomp_ran_nlines=0

_tcomp_ran_seed() {
  [[ -e $_tcomp_ran_file ]] && return
  local -i n; local line out=''
  for n in ${(on)${(k)history}}; do
    line=${history[$n]}
    [[ -n ${line// } && $line != *[[:cntrl:]]* ]] && out+=$'0\t'"$line"$'\n'
  done
  (umask 077; mkdir -p -- "${_tcomp_ran_file:h}" && print -rn -- "$out" >> "$_tcomp_ran_file")
}

# Load the file into memory when it changed (another session may have added to it).
_tcomp_ran_load() {
  _tcomp_ran_seed
  local -A st; local stamp=''
  zstat -H st "$_tcomp_ran_file" 2>/dev/null && stamp="${st[ino]}:${st[size]}:${st[mtime]}"
  [[ -n $stamp && $stamp == $_tcomp_ran_stamp ]] && return
  local -a lines
  [[ -r $_tcomp_ran_file ]] && lines=( ${(f)"$(<$_tcomp_ran_file)"} )
  local -i index
  local line command
  if [[ -n $_tcomp_ran_stamp && ${stamp%%:*} == ${_tcomp_ran_stamp%%:*} ]] && (( $#lines >= _tcomp_ran_nlines )); then
    # Same file, only appended to (by any session): add just the new lines.
    for line in ${lines[_tcomp_ran_nlines+1,-1]}; do
      command=${line#*$'\t'}
      [[ $line == *$'\t'* && -n $command ]] || continue
      [[ -n ${_tcomp_ran_time[$command]} ]] && _tcomp_ran=( ${_tcomp_ran:#$command} )
      _tcomp_ran_time[$command]=${line%%$'\t'*}
      _tcomp_ran=( "$command" $_tcomp_ran )
    done
    (( $#_tcomp_ran > _tcomp_ran_max )) && _tcomp_ran=( ${_tcomp_ran[1,_tcomp_ran_max]} )
  else
    _tcomp_ran=(); _tcomp_ran_time=()
    for (( index = $#lines; index >= 1; index-- )); do
      line=${lines[index]}
      command=${line#*$'\t'}
      [[ $line == *$'\t'* && -n $command && -z ${_tcomp_ran_time[$command]} ]] || continue
      _tcomp_ran_time[$command]=${line%%$'\t'*}
      _tcomp_ran+=( "$command" )
      (( $#_tcomp_ran >= _tcomp_ran_max )) && break
    done
  fi
  _tcomp_ran_stamp=$stamp
  _tcomp_ran_nlines=$#lines
  # Append-only, so rewrite it once repeats pile up (oldest first, as appended).
  if (( $#lines > 2 * _tcomp_ran_max )); then
    local out='' tmp="$_tcomp_ran_file.$$"
    for command in "${(@Oa)_tcomp_ran}"; do out+="${_tcomp_ran_time[$command]}"$'\t'"$command"$'\n'; done
    if (umask 077; print -rn -- "$out" > "$tmp" && mv -f -- "$tmp" "$_tcomp_ran_file") 2>/dev/null; then
      zstat -H st "$_tcomp_ran_file" 2>/dev/null && _tcomp_ran_stamp="${st[ino]}:${st[size]}:${st[mtime]}"
      _tcomp_ran_nlines=$#_tcomp_ran
    fi
  fi
}

_tcomp_ran_preexec() {
  _tcomp_ran_pending=$1
  # A leading space keeps a command out of history, as hist_ignore_space does.
  [[ $1 == ' '* || -z ${1// } || $1 == *[[:cntrl:]]* ]] && _tcomp_ran_pending=''
}

_tcomp_ran_precmd() {
  local -i rc=$?
  local command=$_tcomp_ran_pending
  _tcomp_ran_pending=''
  (( rc == 0 )) && [[ -n $command ]] || return
  _tcomp_ran_seed   # creates the file private; no fork per prompt after that
  { print -r -- "$EPOCHSECONDS"$'\t'"$command" >> "$_tcomp_ran_file" } 2>/dev/null
}
add-zsh-hook preexec _tcomp_ran_preexec
add-zsh-hook precmd _tcomp_ran_precmd

# "5m", "3h", "2d" for the history menu; blank when the time is unknown.
_tcomp_short_ago() {
  local -i t=$1 s=$(( EPOCHSECONDS - $1 ))
  if (( t == 0 )); then REPLY=''
  elif (( s < 60 )); then REPLY='now'
  elif (( s < 3600 )); then REPLY="$(( s / 60 ))m"
  elif (( s < 86400 )); then REPLY="$(( s / 3600 ))h"
  else REPLY="$(( s / 86400 ))d"; fi
}

# Sets reply to "from to" offsets (0-based, end exclusive) of where the line
# matches $1, the way _tcomp_search_fill matched it: the first occurrence of
# the whole query, else each of its letters in order. False if none.
_tcomp_match_ranges() {
  emulate -L zsh
  setopt extended_glob
  reply=()
  local label=${(L)1} query=${(L)${BUFFER##[[:space:]]#}} char before
  [[ -n $query ]] || return 1
  if [[ $label == *"$query"* ]]; then
    before=${label%%"$query"*}
    reply=( "${#before} $(( ${#before} + ${#query} ))" )
    return 0
  fi
  local -i at=0 found
  for char in ${(s::)query//[[:space:]]/}; do
    # 1-based within the rest; past its end (or 0 when the rest is empty) if absent.
    found=${label[at+1,-1][(i)${(b)char}]}
    (( found >= 1 && found <= ${#label} - at )) || { reply=(); return 1 }
    (( at += found ))
    reply+=( "$(( at - 1 )) $at" )
  done
  (( $#reply ))
}

# Fill the menu with the history matching the line; false if nothing matches.
_tcomp_search_fill() {
  emulate -L zsh
  setopt extended_glob
  _tcomp_hits=(); _tcomp_popular_count=0
  POSTDISPLAY=''
  region_highlight=(${region_highlight:#*memo=tcomp})
  local query=${BUFFER##[[:space:]]#} char fuzzy='' command
  local -a found prefix contains
  if [[ -z $query ]]; then
    found=( "${_tcomp_ran[@]}" )
  else
    prefix=( "${(@M)_tcomp_ran:#(#i)${query}*}" )
    contains=( "${(@M)_tcomp_ran:#(#i)*${query}*}" )
    for char in ${(s::)query//[[:space:]]/}; do fuzzy+="*${(b)char}"; done
    found=( "${(@M)_tcomp_ran:#(#i)${~fuzzy}*}" )
    # Unquoted: an empty difference must add nothing, not one empty row.
    found=( ${found:|contains} )                 # contains ⊇ prefix
    found=( $prefix ${contains:|prefix} $found )
  fi
  # "@<time>" becomes the age column ("3h") when drawn.
  # Unquoted: an empty slice is no rows.
  local -a rows=()
  for command in ${found[1,200]}; do
    rows+=( "$command"$'\t'"$command"$'\t@'"${_tcomp_ran_time[$command]:-0}"$'\thistory' )
  done
  _tcomp_hits=( "${rows[@]}" )
  (( _tcomp_selected > $#_tcomp_hits )) && _tcomp_selected=$#_tcomp_hits
  (( _tcomp_selected < 1 )) && _tcomp_selected=1
  (( $#_tcomp_hits ))
}

# Ctrl+R: search every session's history; again (or Ctrl+G) goes back to completions.
_tcomp_search() {
  if (( _tcomp_search_mode )); then _tcomp_search_close; return; fi
  _tcomp_async_cancel
  _tcomp_hist_mode=0
  _tcomp_ran_load
  _tcomp_search_mode=1
  _tcomp_selected=1
  if ! _tcomp_search_fill; then
    _tcomp_search_mode=0
    _tcomp_preview
    zle -M 'No history matches'
    return
  fi
  _tcomp_render
  zle -R
}

_tcomp_search_close() {
  _tcomp_search_mode=0
  _tcomp_selected=1
  _tcomp_preview
  zle -R
}
zle -N _tcomp_search

# ---------------------------------------------------------------- Tab

_tcomp_tab() {
  _tcomp_refresh_stale
  # 0. Ctrl+R search: fill in the highlighted command.
  if (( _tcomp_search_mode && $#_tcomp_hits )); then
    _tcomp_choose
    return
  fi
  # 1. Abbreviation at the cursor.
  if ! _tcomp_in_hist && _tcomp_abbr_match; then
    _tcomp_abbr_expand "$REPLY"
    return
  fi
  # 2. History menu open: fill in the highlighted command.
  if _tcomp_in_hist; then
    _tcomp_hist_mode=0
    _tcomp_choose
    return
  fi
  # 3. tcomp menu showing: accept the highlighted item, but never a history row.
  if (( CURSOR == ${#BUFFER} && $#_tcomp_hits )); then
    if [[ ${_tcomp_hits[_tcomp_selected]##*$'\t'} == history ]]; then
      local index
      for (( index = 1; index <= $#_tcomp_hits; index++ )); do
        [[ ${_tcomp_hits[index]##*$'\t'} == history ]] || break
      done
      if (( index <= $#_tcomp_hits )); then
        _tcomp_selected=$index
        _tcomp_choose
        return
      fi
    else
      _tcomp_choose
      return
    fi
  fi
  # 4. Nothing to accept: normal zsh Tab.
  zle expand-or-complete
}

# Each prompt starts with the history menu closed.
_tcomp_line_init() { _tcomp_moved=0; _tcomp_hist_mode=0; _tcomp_search_mode=0; _tcomp_cache_buffer=''; _tcomp_async_cancel }
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init _tcomp_line_init

zle -N _tcomp_cancel
zle -N _tcomp_tab
for _tcomp_keymap in emacs viins; do
  bindkey -M "$_tcomp_keymap" '^[[A' _tcomp_up
  bindkey -M "$_tcomp_keymap" '^[OA' _tcomp_up
  bindkey -M "$_tcomp_keymap" '^[[B' _tcomp_down
  bindkey -M "$_tcomp_keymap" '^[OB' _tcomp_down
  bindkey -M "$_tcomp_keymap" '^[[C' _tcomp_choose
  bindkey -M "$_tcomp_keymap" '^[OC' _tcomp_choose
  bindkey -M "$_tcomp_keymap" '^M' _tcomp_accept_line
  bindkey -M "$_tcomp_keymap" '^E' _tcomp_end_of_line
  bindkey -M "$_tcomp_keymap" '^G' _tcomp_cancel
  bindkey -M "$_tcomp_keymap" '^R' _tcomp_search
  bindkey -M "$_tcomp_keymap" '^I' _tcomp_tab
  bindkey -M "$_tcomp_keymap" '^[[Z' expand-or-complete
done
unset _tcomp_keymap
