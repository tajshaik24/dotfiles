#!/usr/bin/env bash
# Install these dotfiles: link config files into $HOME, install Homebrew
# packages, and build tcomp. Safe to run repeatedly.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
TCOMP_DIR="$HOME/.config/tcomp"

# Move a real (non-symlink) file aside before it is replaced by a link.
backup() {
  if [ -e "$1" ] && [ ! -L "$1" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$1" "$BACKUP_DIR/"
    echo "📦 Backed up $1 to $BACKUP_DIR"
  fi
}

# link <path in repo> <target>; -n replaces an existing directory link
# instead of creating a link inside it.
link() {
  backup "$2"
  ln -sfn "$DOTFILES_DIR/$1" "$2"
}

# Homebrew: native arm64 even when this script runs under Rosetta.
if [ -x /opt/homebrew/bin/brew ]; then
  brew() { arch -arm64 /opt/homebrew/bin/brew "$@"; }
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
else
  echo "❌ Homebrew is required. Install it from https://brew.sh, then re-run $0" >&2
  exit 1
fi

echo "🔗 Linking config files..."
link zshrc ~/.zshrc
link .zsh_prompt ~/.zsh_prompt
link tmux.conf ~/.tmux.conf
link vimrc ~/.vimrc
# private_keys is gitignored; keep one from a replaced ~/.zsh_prompt directory.
if [ -f "$BACKUP_DIR/.zsh_prompt/private_keys" ] && [ ! -f "$DOTFILES_DIR/.zsh_prompt/private_keys" ]; then
  cp "$BACKUP_DIR/.zsh_prompt/private_keys" "$DOTFILES_DIR/.zsh_prompt/private_keys"
  chmod 600 "$DOTFILES_DIR/.zsh_prompt/private_keys"
  echo "🔐 Kept your existing private_keys"
fi

echo "📦 Installing Homebrew packages..."
# Homebrew won't load formulae from third-party taps until each is trusted.
# Trust exactly the user/tap/formula entries listed in the Brewfile.
sed -n 's/^brew "\([^"/]*\/[^"/]*\/[^"]*\)".*/\1/p' "$DOTFILES_DIR/Brewfile" |
  while read -r formula; do
    brew tap "${formula%/*}" >/dev/null
    brew trust --formula "$formula" >/dev/null
  done
brew bundle --quiet --file="$DOTFILES_DIR/Brewfile"

# One-time migration from the old setup (Homebrew rfig and
# rex-agent-restore, zsh-autocomplete).
# Runs after brew bundle so rust stays installed. No-op on new machines.
if brew list zsh-autocomplete >/dev/null 2>&1; then
  echo "🧹 Removing zsh-autocomplete (conflicts with tcomp)..."
  brew uninstall zsh-autocomplete
  rm -rf "$HOME/.local/state/zsh-autocomplete" "${ZDOTDIR:-$HOME}"/.zcompdump*
fi
if brew list rfig >/dev/null 2>&1; then
  echo "🧹 Removing Homebrew rfig (replaced by tcomp)..."
  brew uninstall rfig
fi
if brew list rex-agent-restore >/dev/null 2>&1; then
  echo "🧹 Removing Homebrew rex-agent-restore (now in this repo)..."
  brew uninstall rex-agent-restore
fi
for tap in tamia6/tap pattont/rex-agent-restore; do
  if brew tap | grep -qx "$tap"; then
    brew untap "$tap"
  fi
done
# Old Homebrew source line; zshrc now sources the repo copy.
if [ -f "$HOME/.zshrc.local" ] && grep -q '/opt/homebrew/share/rex-agent-restore' "$HOME/.zshrc.local"; then
  sed -i.bak '/^# >>> rex-agent-restore >>>$/,/^# <<< rex-agent-restore <<<$/d' "$HOME/.zshrc.local"
  rm -f "$HOME/.zshrc.local.bak"
fi
rm -f "$HOME/.local/bin/rfig"
if [ -d "$HOME/.config/rfig" ] && [ ! -e "$TCOMP_DIR" ]; then
  echo "🚚 Moving ~/.config/rfig to $TCOMP_DIR (keeps your history)..."
  mv "$HOME/.config/rfig" "$TCOMP_DIR"
  rm -rf "$TCOMP_DIR"/rfig.zsh "$TCOMP_DIR"/abbr.tsv "$TCOMP_DIR"/generated/rfig.* \
    "$TCOMP_DIR"/help/rfig "$TCOMP_DIR"/options/rfig.tsv "$TCOMP_DIR"/fallback/rfig.tsv
fi

echo "🦀 Building tcomp..."
cargo install --quiet --locked --force --path "$DOTFILES_DIR/tcomp" --root "$HOME/.local"
mkdir -p "$TCOMP_DIR"
link tcomp/abbr.tsv "$TCOMP_DIR/abbr.tsv"
if [ ! -f "$TCOMP_DIR/commands.txt" ]; then
  echo "⚙️  Indexing commands for tcomp (one time)..."
  "$HOME/.local/bin/tcomp" setup --shell zsh
fi

# rex-agent-restore: point agent hooks (Claude, Codex, ...) and Rex at the
# repo copy. --no-shell because zshrc sources its shell part directly.
echo "🔁 Setting up rex-agent-restore..."
link rex-agent-restore/bin/rex-agent-restore "$HOME/.local/bin/rex-agent-restore"
"$HOME/.local/bin/rex-agent-restore" install --no-shell >/dev/null
rar_status="$("$HOME/.local/bin/rex-agent-restore" doctor 2>&1 || true)"
case "$rar_status" in
  *"not approved"*) echo "💡 Codex: run /hooks once and approve the rex-agent-restore hook." ;;
esac

# Optional machine name for the prompt, stored in the gitignored private_keys.
if [ -t 0 ]; then
  read -r -p "🏷  Machine name for the prompt (blank to skip): " prompt_name || prompt_name=""
  if [ -n "$prompt_name" ]; then
    keys="$DOTFILES_DIR/.zsh_prompt/private_keys"
    touch "$keys" && chmod 600 "$keys"
    grep -v '^export PROMPT_HOSTNAME=' "$keys" > "$keys.tmp" || true
    printf 'export PROMPT_HOSTNAME=%q\n' "$prompt_name" >> "$keys.tmp"
    mv "$keys.tmp" "$keys"
    echo "✅ Prompt will show: $prompt_name"
  fi
fi

echo "✅ Done. Open a new terminal (or run: exec zsh)."
