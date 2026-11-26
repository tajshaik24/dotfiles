# ── Basics ────────────────────────────────────────────────────────────
autoload -U colors && colors
setopt PROMPT_SUBST
export CLICOLOR=1
# BSD ls colors: bold cyan directories (default dark blue is unreadable on dark backgrounds).
# Pairs (fg+bg): dir, symlink, socket, pipe, exec, block, char, setuid, setgid, sticky-other-w, other-w
export LSCOLORS="Gxfxcxdxbxegedabagacad"
alias grep='grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn}'

# ── Homebrew ──────────────────────────────────────────────────────────
export HOMEBREW_PREFIX="/opt/homebrew"
alias brew="arch -arm64 $HOMEBREW_PREFIX/bin/brew"

# C++ compilation
export LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib -L$HOMEBREW_PREFIX/opt/openssl@3/lib"
export CPPFLAGS="-I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include -I$HOMEBREW_PREFIX/opt/openssl@3/include"

# ── PATH (deduplicated; earlier entries win) ──────────────────────────
export GOPATH="$HOME/go"
export NVM_DIR="$HOME/.nvm"

typeset -U path
path=(
  "$HOME/.local/bin"                             # tcomp, Claude Code
  "$HOMEBREW_PREFIX/bin"
  "$HOMEBREW_PREFIX/sbin"
  "$HOMEBREW_PREFIX/opt/openssl@3/bin"
  $path
  "$GOPATH/bin"
)

# ── Completion ────────────────────────────────────────────────────────
# Plain compinit (tcomp provides the inline suggestions). Rebuild the dump at most once a day.
fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
autoload -Uz compinit
zcompdump=(${ZDOTDIR:-$HOME}/.zcompdump(N.mh-24))
if (( $#zcompdump )); then compinit -C; else compinit; fi
unset zcompdump

# ── nvm ───────────────────────────────────────────────────────────────
if [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ]; then
  source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
  source "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
elif [ -s "$NVM_DIR/nvm.sh" ]; then
  source "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
fi

# ── conda (auto-detected across machines) ─────────────────────────────
conda_bin=$(command -v conda)
if [ -z "$conda_bin" ]; then
  for conda_base in \
      "$HOMEBREW_PREFIX/Caskroom/miniconda/base" \
      "$HOMEBREW_PREFIX/Caskroom/anaconda/base" \
      "$HOME/miniconda3" \
      "$HOME/anaconda3" \
      "$HOME/.conda" \
      "/usr/local/Caskroom/miniconda/base"; do
    [ -x "$conda_base/bin/conda" ] && conda_bin="$conda_base/bin/conda" && break
  done
fi
if [ -n "$conda_bin" ]; then
  conda_hook="$("$conda_bin" shell.zsh hook 2>/dev/null)" && eval "$conda_hook"
fi
unset conda_bin conda_base conda_hook

# Machine-specific settings (gitignored). Loaded before the repo's prompt,
# aliases and plugins so the repo's definitions win on any overlap.
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# ── Prompt, aliases, git helpers ──────────────────────────────────────
for file in ~/.zsh_prompt/*(N.); do
  [[ $file == *.example ]] || source "$file"
done
unset file

# ── Line editor plugins (keep last) ───────────────────────────────────
# tcomp: inline suggestions. Binary built by install.sh; script sourced from
# the repo so edits apply in new shells.
tcomp_zsh="${${:-$HOME/.zshrc}:A:h}/tcomp/tcomp.zsh"
(( $+commands[tcomp] )) && [ -r "$tcomp_zsh" ] && source "$tcomp_zsh"
unset tcomp_zsh
# Syntax highlighting must be sourced after every other widget is defined.
[ -r "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] \
  && source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

