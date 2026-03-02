#!/bin/bash

# Dotfiles Installation Script
# This script creates symlinks from home directory to dotfiles

set -e

DOTFILES_DIR="$HOME/Developer/dotfiles"
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

echo "🚀 Installing dotfiles..."

# Create backup directory for any existing non-symlink files
BACKUP_CREATED=false
backup_if_real() {
    local src="$1"
    local target="$2"
    # Only backup if it exists AND is not already a symlink into our dotfiles
    if [ -e "$src" ] && ! [ -L "$src" ]; then
        if [ "$BACKUP_CREATED" = false ]; then
            echo "📦 Backing up existing dotfiles to $BACKUP_DIR"
            mkdir -p "$BACKUP_DIR"
            BACKUP_CREATED=true
        fi
        cp -r "$src" "$target"
    fi
}

backup_if_real ~/.zshrc "$BACKUP_DIR/"
backup_if_real ~/.tmux.conf "$BACKUP_DIR/"
backup_if_real ~/.vimrc "$BACKUP_DIR/"
backup_if_real ~/.zsh_prompt "$BACKUP_DIR/"

# Preserve private_keys if it exists
PRIVATE_KEYS_BACKUP=""
if [ -f ~/.zsh_prompt/private_keys ]; then
    echo "🔐 Preserving existing private_keys file..."
    PRIVATE_KEYS_BACKUP=$(mktemp)
    cp ~/.zsh_prompt/private_keys "$PRIVATE_KEYS_BACKUP"
fi

# Remove existing files/symlinks
echo "🗑️  Removing existing dotfiles..."
rm -f ~/.zshrc ~/.tmux.conf ~/.vimrc
rm -rf ~/.zsh_prompt

# Create symlinks
echo "🔗 Creating symlinks..."
ln -sf "$DOTFILES_DIR/zshrc" ~/.zshrc
ln -sf "$DOTFILES_DIR/.zsh_prompt" ~/.zsh_prompt

# Optional files (only link if they exist in dotfiles)
[ -f "$DOTFILES_DIR/tmux.conf" ] && ln -sf "$DOTFILES_DIR/tmux.conf" ~/.tmux.conf
[ -f "$DOTFILES_DIR/vimrc" ] && ln -sf "$DOTFILES_DIR/vimrc" ~/.vimrc

# Restore private_keys if it was backed up
if [ -n "$PRIVATE_KEYS_BACKUP" ] && [ -f "$PRIVATE_KEYS_BACKUP" ]; then
    echo "🔐 Restoring private_keys file..."
    cp "$PRIVATE_KEYS_BACKUP" ~/.zsh_prompt/private_keys
    chmod 700 ~/.zsh_prompt/private_keys
    rm "$PRIVATE_KEYS_BACKUP"
elif [ ! -f ~/.zsh_prompt/private_keys ] && [ -f "$DOTFILES_DIR/.zsh_prompt/private_keys.example" ]; then
    echo "💡 No private_keys found. Copy private_keys.example to private_keys and add your keys:"
    echo "   cp ~/.zsh_prompt/private_keys.example ~/.zsh_prompt/private_keys"
fi

echo "✅ Dotfiles installed successfully!"
if [ "$BACKUP_CREATED" = true ]; then
    echo "📝 Backup saved to: $BACKUP_DIR"
fi
echo ""
echo "🔄 To apply changes, run: source ~/.zshrc"
