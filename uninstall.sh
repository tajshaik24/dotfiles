#!/usr/bin/env bash
# Remove what install.sh set up: links, the tcomp binary, and
# rex-agent-restore's agent hooks. Leaves Homebrew packages, ~/.config/tcomp
# (history), saved chat records, and the repo itself untouched.
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
# Remove agent hooks and Rex actions before the program they call.
if [ -x ~/.local/bin/rex-agent-restore ]; then
  ~/.local/bin/rex-agent-restore uninstall >/dev/null
  echo "  ✓ Removed rex-agent-restore hooks"
fi
unlink_if_ours ~/.local/bin/rex-agent-restore
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
