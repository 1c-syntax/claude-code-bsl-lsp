# BSL Language Server — Claude Code Plugin

[Claude Code](https://docs.claude.com/en/docs/claude-code/overview) plugin that integrates [BSL Language Server](https://github.com/1c-syntax/bsl-language-server) as an LSP server for 1C:Enterprise (BSL) and [OneScript](http://oscript.io) (OS) files.

## Features

Provides Claude Code with code intelligence for `.bsl` and `.os` files via Language Server Protocol:

- Diagnostics (code quality checks)
- Go to definition
- Find references
- Hover information
- Code actions and quick fixes
- Symbol navigation
- Formatting
- **Auto-update** — checks for new releases on session start

## Installation

### Via Claude Code CLI

Add this repository as a plugin marketplace, then install the plugin:

```bash
claude
/plugin marketplace add 1c-syntax/claude-code-bsl-lsp
/plugin install bsl-language-server@bsl-language-server
```

### Manual

Clone this repository and add it as a local marketplace:

```bash
git clone https://github.com/1c-syntax/claude-code-bsl-lsp.git
claude
/plugin marketplace add /path/to/claude-code-bsl-lsp
/plugin install bsl-language-server@bsl-language-server
```

## How It Works

On each session start the plugin:

1. Checks if BSL Language Server is already installed
2. Queries the GitHub API for the latest release (throttled to once per 8 minutes)
3. Downloads and installs the native binary if a newer version is available
4. Points the LSP launcher `${CLAUDE_PLUGIN_DATA}/bin/bsl-language-server` at the installed version
5. Cleans up old versions automatically

The LSP server is started via that launcher (see `.lsp.json`), so it works without adding anything to `PATH`.

### Platform-Specific Binary Paths

| Platform | Archive | Binary path after extraction |
|----------|---------|------------------------------|
| Linux    | `bsl-language-server_nix.zip` | `bsl-language-server/bin/bsl-language-server` |
| macOS    | `bsl-language-server_mac.zip` | `bsl-language-server.app/Contents/MacOS/bsl-language-server` |
| Windows  | `bsl-language-server_win.zip` | `bsl-language-server/bsl-language-server.exe` |

### Install Locations

| Platform | Data directory | LSP launcher (`${CLAUDE_PLUGIN_DATA}/bin`) |
|----------|---------------|--------------------------------------------|
| Linux / macOS | `~/.local/share/bsl-language-server/` | symlink `bsl-language-server` → binary (also linked to `~/.local/bin`) |
| Windows       | `%LOCALAPPDATA%\Programs\bsl-language-server\` | directory junction → `vX.Y.Z\bsl-language-server\` (contains `bsl-language-server.exe`) |

`${CLAUDE_PLUGIN_DATA}` is the plugin's persistent data directory provided by Claude Code (`~/.claude/plugins/data/<plugin-id>/`). On Windows the launcher is a junction rather than a copy because the jpackage launcher resolves its `app\` and `runtime\` directories relative to its own location.

## Prerequisites

The plugin automatically downloads BSL Language Server on first session start. It requires a Claude Code version that provides `${CLAUDE_PLUGIN_DATA}` to plugins.

If automatic installation fails, install manually:

1. Download the latest release for your platform from [GitHub Releases](https://github.com/1c-syntax/bsl-language-server/releases/latest).
2. Extract it into the data directory above as `vX.Y.Z/`, so the binary ends up at `vX.Y.Z/<binary path after extraction>` (see the table above).
3. Create `SERVER-INFO` in the data directory with `{"version":"vX.Y.Z","lastUpdate":0}`.
4. Start a new session — the hook uses the version recorded in `SERVER-INFO` and creates the launcher for it (it does not scan `vX.Y.Z/` directories on its own).

### Windows Note

On Windows, the plugin works via both:
- **Git Bash** (comes with [Git for Windows](https://git-scm.com/download/win)) — used by default
- **PowerShell 6+** — fallback if bash is not available

## Development

Run the hook tests (bash tests require `jq`, `zip`, `unzip`; PowerShell tests require PowerShell 7+):

```bash
bash tests/check-bsl-ls.test.sh
pwsh -NoProfile -File tests/check-bsl-ls.test.ps1
```

CI runs both suites on Linux, macOS and Windows (`.github/workflows/test.yml`); on Windows the launcher is a real directory junction.

## Configuration

BSL Language Server can be configured via `.bsl-language-server.json` in your project root. See the [BSL Language Server documentation](https://1c-syntax.github.io/bsl-language-server/en) for available options.

## Supported File Types

| Extension | Language                        |
|-----------|---------------------------------|
| `.bsl`    | 1C:Enterprise (BSL)             |
| `.os`     | OneScript                       |

## Links

- [BSL Language Server](https://github.com/1c-syntax/bsl-language-server)
- [Claude Code Documentation](https://docs.claude.com/en/docs/claude-code/overview)
- [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
