# Sourced by ~/.zshrc after installing tcomp.
if (( ! $+functions[_main_complete] )); then
  autoload -Uz compinit
  compinit -D
fi
zmodload zsh/stat
zmodload zsh/zutil

typeset -gaU _tcomp_hits
typeset -gA _tcomp_option_kinds
typeset -gA _tcomp_branch_candidates
typeset -gA _tcomp_usage
_tcomp_usage=()
typeset -g _tcomp_option_source='' _tcomp_option_stamp=''
typeset -g _tcomp_history_match=''
typeset -g _tcomp_history_dir=''
typeset -ga _tcomp_history_lines
typeset -gi _tcomp_selected=1 _tcomp_pulse=0 _tcomp_injected=0 _tcomp_popular_count=0
typeset -gA _tcomp_abbr
typeset -g _tcomp_abbr_file="$HOME/.config/tcomp/abbr.tsv" _tcomp_abbr_stamp=''
typeset -gi _tcomp_hist_mode=0 _tcomp_hist_max=20

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
  local dir line file="$HOME/.config/tcomp/history.tsv"
  [[ -r $file ]] || return
  while IFS=$'\x1f' read -r dir line; do
    [[ $dir == $_tcomp_history_dir && -n $line ]] || continue
    _tcomp_history_lines+=( "$line" )
  done < "$file"
  (( $#_tcomp_history_lines > 1000 )) && _tcomp_history_lines=( "${_tcomp_history_lines[-1000,-1][@]}" )
}

_tcomp_history_record() {
  local line=$1 file="$HOME/.config/tcomp/history.tsv"
  [[ -n $line && $line != *$'\n'* && $line != *$'\r'* && $line != *$'\x1f'* \
    && $PWD != *$'\n'* && $PWD != *$'\r'* && $PWD != *$'\x1f'* ]] || return
  [[ -o hist_ignore_space && $line == ' '* ]] && return
  (umask 077; mkdir -p -- "${file:h}" && touch -- "$file" && chmod 600 "$file" && printf '%s\x1f%s\n' "$PWD" "$line" >> "$file") || return
  [[ $_tcomp_history_dir == $PWD ]] || _tcomp_history_load_dir
  _tcomp_history_lines+=( "$line" )
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

_tcomp_history_suggest() {
  _tcomp_history_match=''
  [[ -n $BUFFER && $CURSOR == ${#BUFFER} && $BUFFER != *$'\n'* ]] || return
  local suggestion
  for suggestion in "${(@Oa)_tcomp_history_lines}"; do
    [[ $suggestion == "$BUFFER"* && $suggestion != "$BUFFER" && $suggestion != *[[:cntrl:]]* ]] || continue
    _tcomp_history_match=$suggestion
    return
  done
}

_tcomp_render() {
  region_highlight=(${region_highlight:#*memo=tcomp})
  POSTDISPLAY=''
  (( $#_tcomp_hits )) || { _tcomp_abbr_hint; return }
  local first=$(( _tcomp_selected > 5 ? _tcomp_selected - 4 : 1 ))
  local index description row start kind icon color rest record label icon_offset label_offset width
  local -a popular_icons=( '①' '②' '③' )
  rest=${_tcomp_hits[_tcomp_selected]#*$'\t'}
  rest=${rest#*$'\t'}
  description=${rest%%$'\t'*}
  for (( index = first; index <= $#_tcomp_hits && index < first + 5; index++ )); do
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
    local popular_index=$index
    [[ ${_tcomp_hits[1]##*$'\t'} == history ]] && (( --popular_index ))
    (( popular_index > 0 && popular_index <= _tcomp_popular_count )) && icon=$popular_icons[popular_index]
    POSTDISPLAY+=$'\n'
    start=$(( ${#BUFFER} + ${#POSTDISPLAY} ))
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
    if (( index == _tcomp_selected && _tcomp_pulse )); then
      printf -v row ' ➜ %s   %-*.*s' "$icon" $width $width "$label"
    elif (( index == _tcomp_selected )); then
      printf -v row '→ %s %-*.*s' "$icon" $width $width "$label"
    elif (( _tcomp_pulse && (index == _tcomp_selected - 1 || index == _tcomp_selected + 1) )); then
      printf -v row '  %s  %-*.*s' "$icon" $width $width "$label"
    else
      printf -v row '  %s %-*.*s' "$icon" $width $width "$label"
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
  POSTDISPLAY+=$'\n'
  width=$(( COLUMNS > 2 ? COLUMNS - 2 : 0 ))
  (( width > 44 )) && width=44
  printf -v row ' %-*.*s' $width $width "$description"
  POSTDISPLAY+=$row
  _tcomp_abbr_hint
}

_tcomp_complete() {
  POSTDISPLAY=''
  region_highlight=(${region_highlight:#*memo=tcomp})
  _tcomp_hits=()
  _tcomp_branch_candidates=()
  _tcomp_popular_count=0
  _tcomp_injected=0
  [[ -n $BUFFER && $BUFFER != *$'\n'* ]] || return

  local original_buffer=$BUFFER original_cursor=$CURSOR command_name=${BUFFER%% *} record
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

  (( $#_tcomp_hits )) || return
  local -a subcommands flags
  local label typed_prefix=${original_buffer[$((_tcomp_start + 1)),$original_cursor]}
  if (( $#_tcomp_branch_candidates )); then
    local -a branch_hits
    for record in "${_tcomp_hits[@]}"; do
      label=${record%%$'\t'*}
      [[ $label == -* || -n ${_tcomp_branch_candidates[$label]-} ]] && branch_hits+=( "$record" )
    done
    _tcomp_hits=( "${branch_hits[@]}" )
  fi
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
  _tcomp_complete
  _tcomp_history_suggest
  if [[ -n $_tcomp_history_match ]]; then
    _tcomp_hits=( "$_tcomp_history_match"$'\t'"$_tcomp_history_match"$'\tHistory\thistory' "${_tcomp_hits[@]}" )
  fi
  (( _tcomp_selected > $#_tcomp_hits )) && _tcomp_selected=$#_tcomp_hits
  (( _tcomp_selected < 1 )) && _tcomp_selected=1
  _tcomp_render
}

_tcomp_after_edit() {
  zle ".$WIDGET" "$@"
  _tcomp_selected=1
  _tcomp_pulse=0
  _tcomp_preview
  zle -R
}
for _tcomp_widget in self-insert backward-delete-char delete-char backward-kill-word kill-word kill-whole-line bracketed-paste backward-char beginning-of-line; do
  zle -N "$_tcomp_widget" _tcomp_after_edit
done
unset _tcomp_widget

_tcomp_redraw_move() {
  local previous=$1
  if (( $#_tcomp_hits )); then
    if (( previous != _tcomp_selected )); then
      _tcomp_pulse=1
      _tcomp_render
      zle -R
      sleep 0.06
      _tcomp_pulse=0
    fi
    _tcomp_render
  else
    _tcomp_preview
  fi
  zle -R
}

_tcomp_up() {
  local previous=$_tcomp_selected
  if _tcomp_in_hist; then
    # History menu lists newest first, so Up walks further back in time.
    (( _tcomp_selected < $#_tcomp_hits )) && (( _tcomp_selected++ ))
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
  local previous=$_tcomp_selected
  if _tcomp_in_hist; then
    if (( _tcomp_selected == 1 )); then
      _tcomp_hist_close
      zle -R
      return
    fi
    (( _tcomp_selected-- ))
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
  if (( $#_tcomp_hits != $#previous_hits )); then
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

_tcomp_accept_line() {
  if _tcomp_in_hist; then
    # Enter in the history menu runs the highlighted command, like Up + Enter.
    local record=${_tcomp_hits[_tcomp_selected]}
    BUFFER=${${record#*$'\t'}%%$'\t'*}
    CURSOR=${#BUFFER}
  fi
  _tcomp_hist_mode=0
  _tcomp_history_record "$BUFFER"
  _tcomp_record_line "$BUFFER"
  POSTDISPLAY=''
  _tcomp_history_match=''
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

# Yellow "⇥ expansion" line under the prompt whenever Tab would expand an abbreviation.
_tcomp_abbr_hint() {
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

_tcomp_in_hist() {
  [[ -z $BUFFER ]] && (( _tcomp_hist_mode && $#_tcomp_hits ))
}

_tcomp_hist_open() {
  local line; local -A seen
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

# Escape-ish: Ctrl+G closes the history menu.
_tcomp_cancel() {
  if _tcomp_in_hist; then _tcomp_hist_close; zle -R; else zle send-break; fi
}

# ---------------------------------------------------------------- Tab

_tcomp_tab() {
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
_tcomp_line_init() { _tcomp_hist_mode=0 }
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
  bindkey -M "$_tcomp_keymap" '^I' _tcomp_tab
  bindkey -M "$_tcomp_keymap" '^[[Z' expand-or-complete
done
unset _tcomp_keymap
