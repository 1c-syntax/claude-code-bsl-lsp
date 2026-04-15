# BSL Language Server — Claude Code Plugin

[Claude Code](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) plugin that integrates [BSL Language Server](https://github.com/1c-syntax/bsl-language-server) as an LSP server for 1C:Enterprise (BSL) and [OneScript](http://oscript.io) (OS) files.

## Features

Provides Claude Code with code intelligence for `.bsl` and `.os` files via Language Server Protocol:

- Diagnostics (code quality checks)
- Go to definition
- Find references
- Hover information
- Code actions and quick fixes
- Symbol navigation
- Formatting

## Installation

### Via Claude Code CLI

```bash
copilot /plugin install 1c-syntax/claude-bsl-ls
```

### Manual

Clone this repository and register it as a local plugin:

```bash
git clone https://github.com/1c-syntax/claude-bsl-ls.git
copilot /plugin add /path/to/claude-bsl-ls
```

## Prerequisites

The plugin automatically downloads BSL Language Server on first session start. If automatic installation fails, install manually:

### Option 1: Native binary (recommended)

Download the latest release for your platform from [GitHub Releases](https://github.com/1c-syntax/bsl-language-server/releases/latest) and place the `bsl-language-server` binary in your `PATH` (e.g., `~/.local/bin/`).

### Option 2: Java JAR

Requires **Java 17+**.

```bash
# Download the executable JAR
curl -fsSL -o ~/.local/bin/bsl-language-server.jar \
  https://github.com/1c-syntax/bsl-language-server/releases/latest/download/bsl-language-server-0.29.0-exec.jar

# Create a wrapper script
cat > ~/.local/bin/bsl-language-server << 'EOF'
#!/bin/bash
exec java -jar "$(dirname "$0")/bsl-language-server.jar" "$@"
EOF
chmod +x ~/.local/bin/bsl-language-server
```

## Configuration

BSL Language Server can be configured via `.bsl-language-server.json` in your project root. See the [BSL Language Server documentation](https://1c-syntax.github.io/bsl-language-server/en) for available options.

## Supported File Types

| Extension | Language                        |
|-----------|---------------------------------|
| `.bsl`    | 1C:Enterprise (BSL)             |
| `.os`     | OneScript                       |

## Links

- [BSL Language Server](https://github.com/1c-syntax/bsl-language-server)
- [Claude Code Documentation](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
- [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
