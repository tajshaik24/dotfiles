# ZSH Customization
autoload colors && colors
setopt PROMPT_SUBST
export CLICOLOR=1

# C++ Compilation
export LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib -L/opt/homebrew/opt/openblas/lib -L/opt/homebrew/opt/openssl@3/lib"
export CPPFLAGS="-I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib -I/opt/homebrew/opt/openssl@3/include -I/opt/homebrew/opt/openblas/include"

# Homebrew
alias brew="arch -arm64 /opt/homebrew/bin/brew"
export PATH="/opt/homebrew/bin:/opt/homebrew/opt/openssl@3/bin:/opt/homebrew/opt/gnu-sed/libexec/gnubin:/opt/homebrew/sbin:$PATH"

FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
source /opt/homebrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=/opt/homebrew/share/zsh-syntax-highlighting/highlighters

# Go development
export GOPATH="${HOME}/go"
export GOROOT="$(brew --prefix golang)/libexec"
export PATH="$PATH:${GOPATH}/bin:${GOROOT}/bin:${GOPATH}/src"

# Claude Code
export PATH="$HOME/.local/bin:$PATH"

## Grep Options
grep-flag-available() {
    echo | grep $1 "" >/dev/null 2>&1
}

GREP_OPTIONS=""

# color grep results
if grep-flag-available --color=auto; then
    GREP_OPTIONS+=" --color=auto"
fi

# ignore VCS folders (if the necessary grep flags are available)
VCS_FOLDERS="{.bzr,CVS,.git,.hg,.svn}"

if grep-flag-available --exclude-dir=.cvs; then
    GREP_OPTIONS+=" --exclude-dir=$VCS_FOLDERS"
elif grep-flag-available --exclude=.cvs; then
    GREP_OPTIONS+=" --exclude=$VCS_FOLDERS"
fi

# export grep settings
alias grep="grep $GREP_OPTIONS"

# ngrok Completions
if command -v ngrok &>/dev/null; then
    eval "$(ngrok completion)"
fi

# clean up
unset GREP_OPTIONS
unset VCS_FOLDERS
unfunction grep-flag-available

# >>> conda initialize >>>
# Auto-detect conda installation across different machines
if command -v conda &>/dev/null; then
    # Conda is already in PATH, use it directly
    __conda_setup="$(conda 'shell.zsh' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    fi
    unset __conda_setup
else
    # Try common conda installation locations
    CONDA_LOCATIONS=(
        "/opt/homebrew/Caskroom/miniconda/base"
        "/opt/homebrew/Caskroom/anaconda/base"
        "$HOME/miniconda3"
        "$HOME/anaconda3"
        "$HOME/.conda"
        "/usr/local/Caskroom/miniconda/base"
    )

    for CONDA_PATH in "${CONDA_LOCATIONS[@]}"; do
        if [ -f "$CONDA_PATH/bin/conda" ]; then
            __conda_setup="$($CONDA_PATH/bin/conda 'shell.zsh' 'hook' 2> /dev/null)"
            if [ $? -eq 0 ]; then
                eval "$__conda_setup"
            else
                if [ -f "$CONDA_PATH/etc/profile.d/conda.sh" ]; then
                    . "$CONDA_PATH/etc/profile.d/conda.sh"
                else
                    export PATH="$CONDA_PATH/bin:$PATH"
                fi
            fi
            unset __conda_setup
            break
        fi
    done
    unset CONDA_LOCATIONS CONDA_PATH
fi
# <<< conda initialize <<<

if [ -d ~/.zsh_prompt ]; then
  for file in ~/.zsh_prompt/*; do
    source $file
  done
fi

# Source local configuration (machine-specific settings)
# This file is not tracked in git - use it for work-specific configs
if [ -f ~/.zshrc.local ]; then
  source ~/.zshrc.local
fi
