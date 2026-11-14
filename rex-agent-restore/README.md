# rex-agent-restore

Brings AI agent chats back when Rex restores your panes after a restart. It's a copy of [pattont/RexAgentRestore](https://github.com/pattont/RexAgentRestore) v0.2.4 (MIT, see `LICENSE`), maintained here instead of being installed from its Homebrew tap.

## How it works

1. Each agent (here Claude Code and Cursor; it also supports Codex, Gemini CLI and others) runs `rex-agent-restore hook <agent>` when a chat starts. The hook records the chat ID for the Rex pane it runs in.
2. When the agent exits normally, the shell's prompt hook (`share/rex-agent-restore/rex-agent-restore.zsh`) deletes that record. Only chats cut off by a restart are kept.
3. When Rex restores a pane, the new shell finds its pane's record and resumes the chat.

## How it's wired up here

`install.sh` does all of this:

- Links `~/.local/bin/rex-agent-restore` to `bin/rex-agent-restore`. Agent hooks call that stable path, so edits here take effect immediately.
- Runs `rex-agent-restore install --no-shell --agents claude,cursor` (the `RAR_AGENTS` list in `install.sh`). This adds the hook to those agents' settings and the Rex actions to `~/.config/rex/init.lua`, linking `~/.config/rex/rex_agent_restore.lua` to `share/`.
- `zshrc` sources the zsh part straight from `share/`. `--no-shell` stops `install` from adding its own source line to the tracked `zshrc`.

Saved chat records live in `~/.local/state/rex-agent-restore/panes`. Check the setup with `rex-agent-restore doctor`.

## Development

```bash
cd rex-agent-restore
make test       # unit tests in a throwaway HOME (needs bash, jq, zsh)
make test-e2e   # restarts a separate throwaway Rex server; your sessions aren't touched
```

The program is a single bash 3.2 script (`bin/rex-agent-restore`). `share/` holds the shell integrations, the Rex Lua actions, and plugins for agents configured by file (OpenCode, Kilo, pi, omp).
