#!/bin/bash

# Dotfiles Uninstallation Script
# This script removes symlinks created by install.sh

set -e

echo "🗑️  Uninstalling dotfiles..."

# Preserve private_keys before removing symlink
PRIVATE_KEYS_BACKUP=""
if [ -L ~/.zsh_prompt ] && [ -f ~/.zsh_prompt/private_keys ]; then
    echo "🔐 Backing up private_keys file..."
    PRIVATE_KEYS_BACKUP="$HOME/.zsh_prompt_private_keys_backup"
    cp ~/.zsh_prompt/private_keys "$PRIVATE_KEYS_BACKUP"
fi

# Remove symlinks
echo "Removing symlinks..."
[ -L ~/.zshrc ] && rm ~/.zshrc && echo "  ✓ Removed ~/.zshrc"
[ -L ~/.tmux.conf ] && rm ~/.tmux.conf && echo "  ✓ Removed ~/.tmux.conf"
[ -L ~/.vimrc ] && rm ~/.vimrc && echo "  ✓ Removed ~/.vimrc"
[ -L ~/.zsh_prompt ] && rm ~/.zsh_prompt && echo "  ✓ Removed ~/.zsh_prompt"

# Notify about private_keys backup
if [ -n "$PRIVATE_KEYS_BACKUP" ] && [ -f "$PRIVATE_KEYS_BACKUP" ]; then
    echo ""
    echo "🔐 Your private_keys file was backed up to:"
    echo "   $PRIVATE_KEYS_BACKUP"
fi

echo ""
echo "✅ Dotfiles uninstalled successfully!"
echo "💡 Your backup files may still exist in ~/dotfiles_backup_* directories"
echo "💡 To restore from backup, copy files from the backup directory"
