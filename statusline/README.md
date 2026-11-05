# status-line

Claude Code status line: `[caveman] Model │ ctx % │ 5h % ↻H:MM │ wk % ↻H:MM │ user`

- Data: status line stdin JSON only (`model`, `context_window`, `rate_limits`). No network, no MCP.
- `rate_limits` only appears on subscription logins, after the first reply of a session (shows `--` before).
- User = `oauthAccount.emailAddress` without `@domain`, from `$CLAUDE_CONFIG_DIR/.claude.json` (or `~/.claude.json`).
- Caveman badge shown if the caveman plugin is installed in that config dir.
- Colors: green <50%, yellow 50–79%, red ≥80%.

## Install
    ./install.sh                  # ~/.claude
    ./install.sh ~/.claude-s2     # specific config dirs
    ./install.sh --all            # ~/.claude + every ~/.claude-* with settings.json
    ./install.sh --list           # show current statusLine per dir
    ./install.sh --uninstall --all
    --dry-run                     # preview

Backups: `settings.json.bak-statusline-<ts>`; previous statusLine kept in `.statusline-prev.json` for uninstall.

## Debug
    touch samples/.capture        # next refresh saves stdin to samples/stdin-<ts>.json
