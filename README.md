# Dotfiles

My personal shell configuration and dotfiles, synchronized across machines.

## What's Included

- **zshrc** - Main ZSH configuration with auto-detecting conda initialization
- **zsh_prompt/** - Custom ZSH prompt, aliases, and themes
  - `aliases` - Custom aliases and functions (includes `sync_dotfiles`)
  - `zsh_theme` - Custom prompt theme
  - `git_completion_custom.zsh` - Git completion settings
  - `plugins/git` - Git helper functions
  - `private_keys.example` - Template for your private keys
  - `private_keys` - Your actual private keys (gitignored, not tracked)

## Quick Start

### Fresh Installation

```bash
# Clone the repository
git clone <your-repo-url> ~/Developer/dotfiles

# Run the install script
cd ~/Developer/dotfiles
chmod +x install.sh
./install.sh

# Reload your shell
source ~/.zshrc
```

### Updating on Existing Machine

```bash
cd ~/Developer/dotfiles
git pull
source ~/.zshrc
```

### Syncing Changes

After making changes to your dotfiles:

```bash
cd ~/Developer/dotfiles
git add .
git commit -m "Update dotfiles"
git push
```

## Uninstall

```bash
cd ~/Developer/dotfiles
chmod +x uninstall.sh
./uninstall.sh
```

## How It Works

The install script creates symlinks from your home directory to this repository:
- `~/.zshrc` → `~/Developer/dotfiles/zshrc`
- `~/.zsh_prompt/` → `~/Developer/dotfiles/.zsh_prompt/`
- `~/.tmux.conf` → `~/Developer/dotfiles/tmux.conf` (if exists)
- `~/.vimrc` → `~/Developer/dotfiles/vimrc` (if exists)

This means any changes you make are automatically tracked in the repository.

## Managing Private Keys

The `private_keys` file contains sensitive API keys and credentials that should **never** be committed to git.

### First Time Setup
```bash
# Copy the example file
cp ~/.zsh_prompt/private_keys.example ~/.zsh_prompt/private_keys

# Edit with your actual keys
vim ~/.zsh_prompt/private_keys
```

### On New Machines
The install script will:
- ✅ Preserve your existing `private_keys` if you already have one
- 💡 Prompt you to create one from the example if you don't

You'll need to manually copy your keys to new machines (use a password manager or secure method).

## Conda Configuration

The `zshrc` file auto-detects conda installations across different machines by checking common locations:
- `/opt/homebrew/Caskroom/miniconda/base` (Homebrew on Apple Silicon)
- `~/miniconda3` or `~/anaconda3` (user installations)
- And several other common paths

No manual configuration needed - just install conda and it will be detected automatically.

## Notes

- The `private_keys` file is gitignored for security and preserved during install/uninstall
- Backups are automatically created during installation
- All scripts are safe to run multiple times
- Conda initialization adapts to different installation locations
