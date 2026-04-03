# Claude Loves Shelly

Claude plugin to open commands in an external terminal window. Run interactive programs, long-running processes, and saved command bookmarks in a real, platform-native terminal.

> **Note:** Claude Code has a built-in `!` bash mode that runs commands inline and feeds output back to Claude. Shelly is different — it opens a real terminal window for interactive use, long-running processes, and anything that needs a full terminal (vim, htop, ssh, etc).

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
>ls -la
>git status
>npm test
/shelly docker ps
/SHELLY ping localhost
```

Commands open in a new external terminal window so you can see output and interact with the process.

## Bookmarks

Save frequently used commands and run them with a short name.

### Save a bookmark
```
>+build npm run build
>+deploy git push {1} {2}
>+log cat {transcript_path} | grep {1}
/shelly +dev npm run dev
```

### Run a bookmark
```
>build
>deploy origin main
>log error
/shelly dev
```

### Look up a bookmark
```
>+build
```

### List all bookmarks
```
>+
```

### Remove a bookmark
```
>-build
```

Bookmarks support positional arguments (`{1}`, `{2}`, ...) and template variables, all resolved at run time.

## Template Variables

Commands and bookmarks can include template variables that get replaced with hook input values:

```
>echo {session_id}
>cat "{transcript_path}"
>echo "Working in {cwd} with mode {permission_mode}"
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

A `UserPromptSubmit` hook intercepts prompts starting with `>` or `/shelly` (case-insensitive), extracts the command, and opens it in a platform-native terminal:

| Platform | Terminal |
|----------|----------|
| Windows  | Windows Terminal (`wt.exe`) > PowerShell (`powershell.exe`) > `cmd.exe` |
| macOS    | Terminal.app via `osascript` |
| Linux    | `x-terminal-emulator`, `gnome-terminal`, `konsole`, `xfce4-terminal`, or `xterm` |

## License

MIT
