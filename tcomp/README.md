# tcomp

Inline command completion and directory-scoped history for zsh. It's a personal fork of [rfig](https://github.com/tamia6/rfig) v0.3.1 (MIT, see `LICENSE`), maintained here independently. Usage and key bindings are in the [main README](../README.md#tcomp-inline-completion).

## How it works

- **`tcomp.zsh`** does all the interactive work. It hooks zsh's line editor, runs zsh's own completion system silently to collect candidates (overriding `compadd`), ranks them with history and usage, and draws the menu under the prompt. `zshrc` sources this file straight from the repo.
- **The `tcomp` binary** (Rust, `src/`) handles the slow or offline parts:
  - `tcomp setup`: indexes commands on `PATH` and starts a background job that parses `--help` output into option catalogs.
  - `tcomp external <cmd> <line>`: completions for commands zsh can't complete itself, borrowed from bash/fish completion scripts (`shell/*-provider.*`) inside a sandbox (`src/sandbox.rs`).
- **Data** lives in `~/.config/tcomp/`: `history.tsv` (per-directory history), `usage.log` (ranking), `abbr.tsv` (link to `abbr.tsv` here), and generated catalogs in `options/`, `help/`, `fallback/` and `generated/`. Delete the catalogs and run `tcomp setup` to rebuild them.

`tcomp.bash` and `tcomp.fish` are the upstream integrations for those shells. They're unused here but still compiled into the binary.

## Development

```bash
cd tcomp
cargo test                    # Rust unit tests
cargo clippy --all-targets    # lint (currently clean)
python3 tests/zsh_features.py # end-to-end zsh test in tmux: expects "all 18 checks OK"
```

- **Editing `tcomp.zsh`:** open a new shell to try it. Nothing needs rebuilding, because `zshrc` sources the repo copy.
- **Editing `src/`:** rebuild with `../install.sh`, or with `cargo install --locked --force --path . --root ~/.local`.

The tmux test runs against whichever `tcomp` is on `PATH`, in a temporary `$HOME`. Your real history and config are never touched.
