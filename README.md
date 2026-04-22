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
4. Cleans up old versions automatically

### Platform-Specific Binary Paths

| Platform | Archive | Binary path after extraction |
|----------|---------|------------------------------|
| Linux    | `bsl-language-server_nix.zip` | `bsl-language-server/bin/bsl-language-server` |
| macOS    | `bsl-language-server_mac.zip` | `bsl-language-server.app/Contents/MacOS/bsl-language-server` |
| Windows  | `bsl-language-server_win.zip` | `bsl-language-server/bsl-language-server.exe` |

### Install Locations

| Platform | Data directory | Symlink / wrapper |
|----------|---------------|-------------------|
| Linux / macOS | `~/.local/share/bsl-language-server/` | `~/.local/bin/bsl-language-server` |
| Windows       | `%LOCALAPPDATA%\Programs\bsl-language-server\` | — (add binary dir to PATH) |

## Prerequisites

The plugin automatically downloads BSL Language Server on first session start. If automatic installation fails, install manually:

Download the latest release for your platform from [GitHub Releases](https://github.com/1c-syntax/bsl-language-server/releases/latest) and place the `bsl-language-server` binary in your `PATH`.

### Windows Note

On Windows, the plugin works via both:
- **Git Bash** (comes with [Git for Windows](https://git-scm.com/download/win)) — used by default
- **PowerShell 6+** — fallback if bash is not available

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
