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
export LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib -L$HOMEBREW_PREFIX/opt/openblas/lib -L$HOMEBREW_PREFIX/opt/openssl@3/lib"
export CPPFLAGS="-I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib -I$HOMEBREW_PREFIX/opt/openssl@3/include -I$HOMEBREW_PREFIX/opt/openblas/include"

# ── PATH (deduplicated; earlier entries win) ──────────────────────────
export GOPATH="$HOME/go"
export BUN_INSTALL="$HOME/.bun"
export NVM_DIR="$HOME/.nvm"

typeset -U path
path=(
  "$HOME/.bin"                                   # personal scripts
  "$HOME/.local/bin"                             # Claude Code
  "$BUN_INSTALL/bin"
  "$HOMEBREW_PREFIX/bin"
  "$HOMEBREW_PREFIX/sbin"
  "$HOMEBREW_PREFIX/opt/openssl@3/bin"
  "$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin"
  $path
  "$GOPATH/bin"
)

# ── Completion ────────────────────────────────────────────────────────
# Plain compinit (rfig provides the inline suggestions). Rebuild the dump at most once a day.
fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
autoload -Uz compinit
zcompdump=(${ZDOTDIR:-$HOME}/.zcompdump(N.mh-24))
if (( $#zcompdump )); then compinit -C; else compinit; fi
unset zcompdump

[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"
command -v ngrok &>/dev/null && eval "$(ngrok completion)"

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

# ── Prompt, aliases, git helpers ──────────────────────────────────────
for file in ~/.zsh_prompt/*(N.); do
  [[ $file == *.example ]] || source "$file"
done
unset file

# Machine-specific settings (gitignored)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# ── Line editor plugins (keep last) ───────────────────────────────────
# rfig: inline command suggestions. The zsh script is vendored in this repo
# (rfig/rfig.zsh: Tab accepts, abbreviations, Up-on-empty history menu);
# the binary comes from Homebrew. Falls back to rfig's stock script.
rfig_zsh="${${:-$HOME/.zshrc}:A:h}/rfig/rfig.zsh"
[ -r "$rfig_zsh" ] || rfig_zsh="$HOME/.config/rfig/rfig.zsh"
(( $+commands[rfig] )) && [ -r "$rfig_zsh" ] && source "$rfig_zsh"
unset rfig_zsh
# Syntax highlighting must be sourced after every other widget is defined.
[ -r "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] \
  && source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
