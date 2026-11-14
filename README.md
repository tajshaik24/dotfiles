# dotfiles

My macOS shell setup: zsh, a custom prompt, tmux, vim, and **tcomp**, my own inline command completion.

## Install

```bash
git clone git@github.com:tajshaik24/dotfiles.git ~/Developer/dotfiles
~/Developer/dotfiles/install.sh
exec zsh
```

Requires [Homebrew](https://brew.sh). `install.sh` is safe to re-run. It:

1. Links `~/.zshrc`, `~/.zsh_prompt`, `~/.tmux.conf` and `~/.vimrc` to this repo, moving any existing real files to `~/dotfiles_backup_<timestamp>/`.
2. Installs everything in the `Brewfile`: shell dependencies, dev tools and apps.
3. Builds tcomp into `~/.local/bin`, links its abbreviations, and indexes your commands once.
4. Optionally asks for a machine name to show in the prompt.

To update another machine: `git pull`, then `./install.sh` if `tcomp/` or the `Brewfile` changed. Otherwise just open a new shell.

## Layout

| Path | What it is |
| --- | --- |
| `zshrc` | PATH, completion, nvm, conda auto-detection, tcomp, syntax highlighting |
| `.zsh_prompt/zsh_theme` | Prompt: user@host, path, git dirty/ahead state; branch, SHA and status on the right |
| `.zsh_prompt/aliases` | `sync_dotfiles`, directory-stack options, `...` global aliases |
| `.zsh_prompt/git_completion_custom.zsh` | Lists the current branch first in git branch completion |
| `.zsh_prompt/plugins/git` | Git prompt helpers (from oh-my-zsh) |
| `.zsh_prompt/private_keys.example` | Template for secrets; copy to `private_keys` (gitignored) |
| `.zshrc.local.example` | Template for per-machine settings in `~/.zshrc.local` (gitignored) |
| `tmux.conf` | Prefix `Ctrl+Q`, mouse, vi copy mode, Solarized colors |
| `vimrc` | Basic vim settings |
| `tcomp/` | tcomp source, zsh script, abbreviations and tests ([details](tcomp/README.md)) |
| `install.sh` / `uninstall.sh` | Set up / remove the links and the tcomp binary |

## tcomp: inline completion

As you type, a menu of candidates appears under the prompt: subcommands, flags with descriptions, paths, branches, and `◷` rows from commands you've run in the current directory.

| Key | Action |
| --- | --- |
| `Tab` | Expand an abbreviation; else accept the highlighted candidate (skipping `◷` history rows); else native completion |
| `Shift+Tab` | Native zsh completion |
| `↑` / `↓` | Move through the menu |
| `↑` on an empty line | Open this directory's recent commands, newest first. `↑` older, `↓` past the newest closes, `Enter` runs, `→` fills in, `Ctrl+G` closes |
| `→` | Accept the highlighted item (a history row fills the whole command) |
| `Enter` | Expand abbreviations, then run. Never accepts a menu suggestion |

**Abbreviations** replace shell aliases. They live in `tcomp/abbr.tsv`: an abbreviation, a tab, then the expansion, where `%|` marks where the cursor lands. Edits apply immediately. Unlike aliases, the full command shows on screen and in history.

- **Enter** expands every abbreviation that starts a command (at the start of the line, or after `;`, `|` or `&`) and runs the result: `ll src` runs `ls -GplAh src`. Words elsewhere are left alone, so `echo ll` prints `ll`.
- **Tab** expands the abbreviation just before the cursor without running it. A yellow `⇥ …` line previews it.
- **`%|`:** if nothing follows, Enter stops there so you can fill it in (`gc -m` gives `git commit -m "▌"`). If arguments follow, a trailing `%|` is dropped (`gpo main` runs `git push origin main`), and an abbreviation with a mid-line `%|` gives way to a shorter one (`gc -m "msg"` runs `git commit -m "msg"`).

| Abbreviation | Expands to |
| --- | --- |
| `gc`, `gca`, `gc -m` | `git commit`, `… --amend --no-edit`, `… -m "▌"` |
| `gcb` | `git checkout` with an fzf branch picker |
| `gco`, `gp`, `gpo`, `gst`, `gl` | `git checkout`, `git push`, `git push origin ▌`, `git status`, `git log --oneline --graph -20` |
| `l` / `lsa`, `ll` | `ls -Gplah`, `ls -GplAh` |
| `md`, `rd` | `mkdir -p`, `rmdir` |
| `-`, `1`…`9` | `cd -`, `cd -N` (directory stack) |
| `brewup` | `brew update; brew upgrade; brew cleanup; brew doctor` |

## Secrets and per-machine settings

- `~/.zsh_prompt/private_keys` (API keys, `PROMPT_HOSTNAME`) is sourced by `zshrc` and gitignored. Start from `private_keys.example`, and copy it between machines with a password manager.
- `~/.zshrc.local` holds machine-specific PATH entries and aliases, and is gitignored.

## Notes

- **Conda:** the prompt shows the active env itself. Run `conda config --set changeps1 false` once per machine so it doesn't appear twice.
- **Don't install zsh-autocomplete:** it rebinds the same widgets as tcomp. `install.sh` removes it if present.
- **Uninstall:** `./uninstall.sh` removes the links and `~/.local/bin/tcomp`. Homebrew packages and `~/.config/tcomp` (history) are kept.
