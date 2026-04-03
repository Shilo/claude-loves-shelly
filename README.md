# Claude Loves Shelly

Claude plugin to run shell commands directly in a Claude session with `!` prefix or `/shelly` command.

## Install

Add the [marketplace](https://github.com/shilo/claude-plugins) and install:
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

## Template Variables

Commands can include template variables that get replaced with hook input values:

```
!echo {session_id}
!cat "{transcript_path}"
!echo "Working in {cwd} with mode {permission_mode}"
```

| Variable | Description |
|----------|-------------|
| `{prompt}` | The raw prompt text |
| `{session_id}` | Current session identifier |
| `{transcript_path}` | Path to conversation JSON |
| `{cwd}` | Current working directory |
| `{permission_mode}` | Current permission mode |
| `{hook_event_name}` | Hook event name |

## How it works

A `UserPromptSubmit` hook intercepts prompts starting with `!` or `/shelly` (case-insensitive), extracts the command, and opens it in a platform-native terminal:

| Platform | Terminal |
|----------|----------|
| Windows  | Windows Terminal (`wt.exe`) > PowerShell (`powershell.exe`) > `cmd.exe` |
| macOS    | Terminal.app via `osascript` |
| Linux    | `x-terminal-emulator`, `gnome-terminal`, `konsole`, `xfce4-terminal`, or `xterm` |

## License

MIT
