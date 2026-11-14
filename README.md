# Dotfiles

My personal shell configuration and dotfiles, synchronized across machines.

## What's Included

- **Brewfile** - Homebrew packages the shell config depends on (rfig, zsh-syntax-highlighting, fzf, tmux); `install.sh` runs it
- **rfig/** - rfig zsh integration with Tab-accept, abbreviations and an Up-arrow history menu (`rfig.zsh`), abbreviations (`abbr.tsv`), and a tmux test
- **zshrc** - Main ZSH configuration: PATH, completion, nvm, auto-detected conda, rfig, syntax highlighting
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
git clone git@github.com:tajshaik24/dotfiles.git ~/Developer/dotfiles
~/Developer/dotfiles/install.sh   # links files, installs the Brewfile, sets up rfig
exec zsh
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

During install you're also prompted (optionally) for a custom machine name shown in the prompt, stored as `PROMPT_HOSTNAME` in the gitignored `~/.zsh_prompt/private_keys`.

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

## Completion (rfig)

Inline command suggestions come from [rfig](https://github.com/tamia6/rfig). The binary comes from Homebrew; the zsh script is vendored at `rfig/rfig.zsh` (upstream v0.3.1 plus local features) and `zshrc` sources it, followed by zsh-syntax-highlighting (which must load last). `install.sh` installs rfig, runs its one-time `rfig setup`, and links `~/.config/rfig/abbr.tsv` to `rfig/abbr.tsv`.

| Key | Behavior |
| --- | --- |
| `Tab` | Expand an abbreviation, else accept the highlighted candidate (skipping `◷` history rows), else native completion |
| `Shift+Tab` | Native zsh completion |
| `↑` on an empty line | Menu of this directory's recent commands, newest first. `↑` older, `↓` past newest closes, `Enter` runs, `→` fills, `Ctrl+G` closes |

**Abbreviations:** edit `rfig/abbr.tsv` (abbreviation, a tab, expansion; `%|` marks where the cursor lands). Changes apply on the next keystroke. They expand only at the start of a command or after `;`, `|`, `&`, and a yellow `⇥ …` line previews them.

**Upgrading rfig:** `brew upgrade rfig`. If upstream changes its `rfig.zsh`, merge those changes into `rfig/rfig.zsh` by hand, then run `python3 rfig/tests/zsh_features.py` (expects `all 18 checks OK`).

Do not install `zsh-autocomplete`: it rebinds the same line-editor widgets and conflicts with rfig.

`rfig setup` appends its own `source ...` line to `~/.zshrc` (which is `zshrc` in this repo); `install.sh` removes it. If you run `rfig setup` by hand, delete that line before committing.

## Conda Configuration

The `zshrc` file auto-detects conda installations across different machines by checking common locations:
- `/opt/homebrew/Caskroom/miniconda/base` (Homebrew on Apple Silicon)
- `~/miniconda3` or `~/anaconda3` (user installations)
- And several other common paths

No manual configuration needed - just install conda and it will be detected automatically.

### Avoiding doubled env prefix in the prompt

The custom theme renders the conda env name itself (via `precmd_conda_info` in `zsh_prompt/zsh_theme`). Conda's shell hook also prepends the env name by default, which causes `(envname)` to appear twice when an env is active. To let the theme own the prefix, disable conda's:

```bash
conda config --set changeps1 false
```

This writes `changeps1: false` to `~/.condarc` and only needs to be run once per machine.

## Notes

- The `private_keys` file is gitignored for security and preserved during install/uninstall
- Backups are automatically created during installation
- All scripts are safe to run multiple times
- Conda initialization adapts to different installation locations
