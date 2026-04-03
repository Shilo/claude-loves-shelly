# Terminal Alias Selection Design

## Summary

Add optional per-command terminal emulator selection via `>!alias` syntax. Users can bypass the default auto-detection cascade and open commands in a specific terminal. All existing behavior is preserved — this is purely additive.

## Syntax

The `!alias` modifier slots in after the `>` or `>>` prefix, before the command:

| Input | Terminal | Mode |
|-------|----------|------|
| `>echo hello` | auto-detect (default) | stay open |
| `>!cmd echo hello` | Command Prompt | stay open |
| `>>echo hello` | auto-detect (inline) | capture output |
| `>>!cmd echo hello` | Command Prompt | capture output |
| `/shelly echo hello` | auto-detect (default) | stay open |
| `/shelly !cmd echo hello` | Command Prompt | stay open |
| `/shelly >echo hello` | auto-detect (inline) | capture output |
| `/shelly >!cmd echo hello` | Command Prompt | capture output |
| `>` | auto-detect (open terminal) | stay open |
| `>!cmd` | Command Prompt (open terminal) | stay open |

All existing syntax without `!` is completely unchanged. The `!alias` extraction only happens when `!` is present.

## Supported Aliases

Predefined short names per platform, each with dedicated invocation logic:

| Platform | Alias | Terminal |
|----------|-------|----------|
| Windows | `wt` | Windows Terminal |
| Windows | `ps` | PowerShell |
| Windows | `cmd` | Command Prompt |
| macOS | `terminal` | Terminal.app |
| macOS | `iterm` | iTerm2 (via osascript) |
| Linux | `xterm` | XTerm |
| Linux | `gnome` | GNOME Terminal |
| Linux | `konsole` | Konsole |
| Linux | `xfce` | Xfce Terminal |

### Error Handling

- **Alias not installed:** `[Claude Loves Shelly - Error]\nTerminal 'iterm' not found.`
- **Alias wrong platform:** `[Claude Loves Shelly - Error]\nTerminal 'cmd' not available on this platform.`

Both follow the existing error output pattern.

## Implementation

All changes are in `scripts/shelly.sh`. No new files.

### 1. Parse `!alias` from CMD

After the existing `>>`/`>` prefix matching extracts `CMD` (around line 30-40), add alias extraction:

```bash
TERMINAL_ALIAS=""
if [ "${CMD#!}" != "$CMD" ]; then
  ALIAS_PART="${CMD#!}"
  TERMINAL_ALIAS=$(printf '%s' "$ALIAS_PART" | cut -d' ' -f1)
  CMD=$(printf '%s' "$ALIAS_PART" | sed "s/^$TERMINAL_ALIAS[[:space:]]*//" )
fi
```

This runs before bookmark routing and template variable substitution, so those features work normally with the cleaned `CMD`.

### 2. External Terminal Dispatch (stay-open mode)

In the platform `case` block (lines 143-240), add a `TERMINAL_ALIAS` check before the existing auto-detect cascade:

```
case "$OS" in
  MINGW*|MSYS*|CYGWIN*)
    if [ -n "$TERMINAL_ALIAS" ]; then
      case "$TERMINAL_ALIAS" in
        wt)   ... ;;
        ps)   ... ;;
        cmd)  ... ;;
        *)    error: alias not available on this platform ;;
      esac
    else
      # existing auto-detect cascade (UNTOUCHED)
    fi
    ;;
  Darwin)
    if [ -n "$TERMINAL_ALIAS" ]; then
      case "$TERMINAL_ALIAS" in
        terminal) ... ;;
        iterm)    ... ;;
        *)        error ;;
      esac
    else
      # existing Terminal.app logic (UNTOUCHED)
    fi
    ;;
  Linux)
    if [ -n "$TERMINAL_ALIAS" ]; then
      case "$TERMINAL_ALIAS" in
        gnome)   ... ;;
        konsole) ... ;;
        xfce)    ... ;;
        xterm)   ... ;;
        *)       error ;;
      esac
    else
      # existing cascade (UNTOUCHED)
    fi
    ;;
esac
```

Each alias block reuses the same invocation logic already written for that terminal in the existing cascade, just accessed directly instead of through auto-detection.

### 3. Inline Capture Mode (`>>`)

For `>>!alias`, the inline capture block (lines 110-132) gets a similar check:

- **Windows `cmd` alias:** Use `cmd.exe /c` instead of `bash -c`. `INLINE_NAME` becomes "Command Prompt".
- **Windows `ps` alias:** Use `powershell -Command` instead of `bash -c`. `INLINE_NAME` becomes "PowerShell".
- **Windows `wt` alias:** Windows Terminal is a terminal emulator, not a shell — use `bash -c` (same as default). `INLINE_NAME` becomes "Git Bash".
- **macOS/Linux aliases:** All aliases use `bash -c` for inline capture since inline mode doesn't open a terminal window. Only the `INLINE_NAME` label changes to reflect the alias name for consistency.
- **No alias set:** Existing `bash -c` capture logic is untouched.

Note: For inline mode, the alias selects the shell used for execution on Windows (where shells differ materially), and only changes the display label on macOS/Linux.

### 4. Alias Validation

Before dispatching, check the alias executable exists with `command -v`. If not found:

```bash
printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''%s'\'' not found."}\n' "$TERMINAL_ALIAS"
exit 0
```

## README Changes

### Cheatsheet — new row

| `>!alias command` | Run command in specific terminal |

### New "Terminal Selection" section (after "Template Variables", before "How it works")

Covers:
- `>!alias` syntax explanation
- Per-platform alias table
- Examples for each platform
- Note that default auto-detection is used without `!alias`

### "How it works" — one sentence addition

Note that `>!alias` bypasses auto-detection to use the specified terminal.

## Constraints

- **No breaking changes:** All existing syntax and behavior is preserved exactly.
- **No regressions:** The auto-detect cascade is only bypassed when `!alias` is explicitly used.
- **Additive only:** New code paths are gated behind `[ -n "$TERMINAL_ALIAS" ]` checks.
