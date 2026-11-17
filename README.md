# dotfiles

My macOS shell setup: zsh, a custom prompt, tmux, vim, **tcomp** (my own inline command completion), and **rex-agent-restore** (resumes agent chats after Rex restarts).

## Install

```bash
git clone git@github.com:tajshaik24/dotfiles.git ~/Developer/dotfiles
~/Developer/dotfiles/install.sh        # shell essentials only (work laptop)
~/Developer/dotfiles/install.sh --all  # also projects and apps (personal Mac)
exec zsh
```

Requires [Homebrew](https://brew.sh). `install.sh` is safe to re-run. It:

1. Links `~/.zshrc`, `~/.zsh_prompt`, `~/.tmux.conf` and `~/.vimrc` to this repo, moving any existing real files to `~/dotfiles_backup_<timestamp>/`.
2. Installs the essentials in `Brewfile`: the shell's dependencies and everyday tools. With `--all`, also the dev tools and apps in `Brewfile.personal`.
3. Builds tcomp into `~/.local/bin`, links its abbreviations, and indexes your commands once.
4. Links rex-agent-restore into `~/.local/bin` and sets up its hooks for Claude Code and Cursor (`RAR_AGENTS` in `install.sh`) and its Rex actions.
5. Optionally asks for a machine name to show in the prompt.

To update another machine: `git pull`, then `./install.sh` (add `--all` on a personal Mac) if `tcomp/src`, a Brewfile or rex-agent-restore's hooks changed. Otherwise just open a new shell.

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
| `rex-agent-restore/` | Resumes Claude Code and Cursor chats when Rex restores a pane ([details](rex-agent-restore/README.md)) |
| `Brewfile` | Essentials: what the shell setup needs plus everyday tools (always installed) |
| `Brewfile.personal` | Dev tools for my projects and apps (`install.sh --all`) |
| `install.sh` / `uninstall.sh` | Set up / remove everything above |

## tcomp: inline completion

As you type, a menu of candidates appears under the prompt: subcommands, flags with descriptions, paths, branches, and `◷` rows from commands you've run in the current directory.

| Key | Action |
| --- | --- |
| `Tab` | Expand an abbreviation; else accept the highlighted candidate (skipping `◷` history rows); else native completion |
| `Shift+Tab` | Native zsh completion |
| `↑` / `↓` | Move through the menu |
| `↑` on an empty line | Open this directory's recent commands, newest first. `↑` older, `↓` past the newest closes, `Enter` runs, `→` fills in, `Ctrl+G` closes |
| `→` | Accept the highlighted item (a history row fills the whole command) |
| `Ctrl+R` | Search every session's history for what's on the line: commands starting with it, then containing it, then with its letters in order (any case), newest first, with the matched letters in yellow. Typing narrows, `↑`/`↓` move, `Enter`, `→` or `Tab` puts one on the line, `Ctrl+R` again or `Ctrl+G` closes. Only commands that exited 0 are kept; the first use imports zsh's history |
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
- `~/.zshrc.local` holds machine-specific PATH entries and aliases, and is gitignored. It loads before the repo's prompt, aliases and tcomp abbreviations, so the repo's definitions win if a name is defined in both.

## Notes

- **Conda:** the prompt shows the active env itself. Run `conda config --set changeps1 false` once per machine so it doesn't appear twice.
- **Don't install zsh-autocomplete:** it rebinds the same widgets as tcomp. `install.sh` removes it if present.
- **Uninstall:** `./uninstall.sh` removes the links, `~/.local/bin/tcomp`, and rex-agent-restore's agent hooks. Homebrew packages, tcomp history and saved chat records are kept.
