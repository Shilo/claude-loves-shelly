# Claude Loves Shelly

Claude plugin to run shell commands directly in a Claude session with `!` prefix or `/shelly` command.

## Install

Add the [Shilo claude-plugins marketplace](https://github.com/shilo/claude-plugins) and install:
```
/plugin marketplace add shilo/claude-plugins
/plugin install claude-loves-shelly@shilo
```

Or clone and load locally:
```bash
git clone https://github.com/shilo/claude-loves-shelly.git
claude --plugin-dir ./claude-loves-shelly
```

## Usage

Type commands directly in your Claude session:

```
!ls -la
!git status
!npm test
/shelly docker ps
/SHELLY ping localhost
```

Commands open in a new external terminal window so you can see output and interact with the process.

## How it works

A `UserPromptSubmit` hook intercepts prompts starting with `!` or `/shelly` (case-insensitive), extracts the command, and opens it in a platform-native terminal:

| Platform | Terminal |
|----------|----------|
| Windows  | `cmd.exe` via `start` |
| macOS    | Terminal.app via `osascript` |
| Linux    | `x-terminal-emulator`, `gnome-terminal`, `konsole`, `xfce4-terminal`, or `xterm` |

## Requirements

- [jq](https://jqlang.github.io/jq/) must be installed and on PATH

## License

MIT
