#!/usr/bin/env bash
# Remove what install.sh set up: links and the tcomp binary. Leaves Homebrew
# packages, ~/.config/tcomp (history), and the repo itself untouched.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Remove a link only if it points into this repo.
unlink_if_ours() {
  if [ -L "$1" ] && [[ "$(readlink "$1")" == "$DOTFILES_DIR"/* ]]; then
    rm "$1"
    echo "  ✓ Removed $1"
  fi
}

echo "🗑️  Uninstalling dotfiles..."
unlink_if_ours ~/.zshrc
unlink_if_ours ~/.zsh_prompt
unlink_if_ours ~/.tmux.conf
unlink_if_ours ~/.vimrc
unlink_if_ours ~/.config/tcomp/abbr.tsv
if [ -x ~/.local/bin/tcomp ]; then
  rm ~/.local/bin/tcomp
  echo "  ✓ Removed ~/.local/bin/tcomp"
fi

echo "✅ Uninstalled. Backups from install.sh are in ~/dotfiles_backup_*."
