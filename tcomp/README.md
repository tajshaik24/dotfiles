# tcomp

Inline command completion and directory-scoped history for zsh. It's a personal fork of [rfig](https://github.com/tamia6/rfig) v0.3.1 (MIT, see `LICENSE`), maintained here independently. Usage and key bindings are in the [main README](../README.md#tcomp-inline-completion).

## How it works

- **`tcomp.zsh`** does all the interactive work. It hooks zsh's line editor, runs zsh's own completion system silently to collect candidates (overriding `compadd`), ranks them with history and usage, and draws the menu under the prompt. `zshrc` sources this file straight from the repo.
  - **Typing never waits on completion.** While you type, completion runs in a background fork of the shell (`zsh/zpty`), and the menu fills in when it finishes (git's completion alone runs about a dozen `git` commands). Tab, Right and Up/Down wait for a pending result, so they never act on a stale menu.
  - **More letters of the same word filter the list already fetched** instead of completing again. Option words (`-`, `--`), paths, an empty word and a bare command name always get a fresh completion, because typing more there can change what's offered.
- **The `tcomp` binary** (Rust, `src/`) handles the slow or offline parts:
  - `tcomp setup`: indexes commands on `PATH` and starts a background job that parses `--help` output into option catalogs.
  - `tcomp external <cmd> <line>`: completions for commands zsh can't complete itself, borrowed from bash/fish completion scripts (`shell/*-provider.*`) inside a sandbox (`src/sandbox.rs`).
- **Data** lives in `~/.config/tcomp/`: `history.tsv` (per-directory history), `ran.tsv` (commands that exited 0, for `Ctrl+R`), `usage.log` (ranking), `abbr.tsv` (link to `abbr.tsv` here), and generated catalogs in `options/`, `help/`, `fallback/` and `generated/`. Delete the catalogs and run `tcomp setup` to rebuild them.

`tcomp.bash` and `tcomp.fish` are the upstream integrations for those shells. They're unused here but still compiled into the binary.

## Development

```bash
cd tcomp
cargo test                    # Rust unit tests
cargo clippy --all-targets    # lint (currently clean)
zsh -f tests/abbr_expand.zsh  # Enter-expansion edge cases
python3 tests/zsh_features.py # end-to-end zsh test in tmux: expects "all 42 checks OK"
```

- **Editing `tcomp.zsh`:** open a new shell to try it. Nothing needs rebuilding, because `zshrc` sources the repo copy.
- **Editing `src/`:** rebuild with `../install.sh`, or with `cargo install --locked --force --path . --root ~/.local`.

The tmux test runs against whichever `tcomp` is on `PATH`, in a temporary `$HOME`. Your real history and config are never touched.
