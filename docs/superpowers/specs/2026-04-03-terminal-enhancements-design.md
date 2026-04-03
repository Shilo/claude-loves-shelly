# Terminal Enhancements Design

Four enhancements to `scripts/shelly.sh` that improve the external terminal experience.

## 1. Echo Command + Window Title

**What:** The terminal displays the command before running it, and the window title reflects what's being executed.

**Title format:** `Shelly — <command>` (em dash separator). For bare `>`, just `Shelly`.

**Echo format:** Prints `> <command>` on the first line, then executes the command. The `>` character must be escaped per platform (`^>` on cmd.exe, `'>'` in bash/sh) to avoid shell redirection.

**Platform behavior:**

| Platform | Title | Echo |
|----------|-------|------|
| Windows/wt.exe | `--title "Shelly — CMD"` | `echo ^> CMD && CMD` |
| Windows/PowerShell | Window title via `start "Shelly — CMD"` | `Write-Host '> CMD'; CMD` |
| Windows/cmd fallback | `start "Shelly — CMD"` | `echo ^> CMD && CMD` |
| macOS/osascript | `set name of front window to "Shelly — CMD"` after `do script` | `echo '> CMD' && CMD` |
| Linux terminals | `-T "Shelly — CMD"` or `--title` flag | `echo '> CMD' && CMD` |

## 2. Working Directory

**What:** All terminal launches open in `$HOOK_CWD` (the directory Claude is working in).

`$HOOK_CWD` is already parsed from the hook JSON input. No new parsing needed.

**Platform behavior:**

| Platform | Method |
|----------|--------|
| Windows/wt.exe | `--startingDirectory "$HOOK_CWD"` |
| Windows/PowerShell fallback | `cd /d "$HOOK_CWD" &&` prefix |
| Windows/cmd fallback | `cd /d "$HOOK_CWD" &&` prefix |
| macOS/osascript | `cd '$HOOK_CWD' &&` prepended to the do script command |
| Linux/gnome-terminal | `--working-directory="$HOOK_CWD"` |
| Linux/konsole | `--workdir "$HOOK_CWD"` |
| Linux/xfce4-terminal | `--working-directory="$HOOK_CWD"` |
| Linux/x-terminal-emulator, xterm | `cd "$HOOK_CWD" &&` prefix in the bash -c string |

## 3. Bare `>` Opens Terminal

**What:** Typing just `>` (with no command) opens a terminal in `$HOOK_CWD` instead of showing a usage message.

- No echo (nothing to echo)
- Window title: just `Shelly`
- Returns `{"decision":"block","reason":"Opened terminal"}`
- The `/shelly` bare form (no args) keeps its current usage-message behavior since it's a different entry point

**Platform behavior:** Same as normal terminal launch, but with no command — just open a shell.

| Platform | Method |
|----------|--------|
| Windows/wt.exe | `wt.exe new-tab --title "Shelly" --startingDirectory "$HOOK_CWD"` |
| Windows/PowerShell | `start "Shelly" powershell -NoExit -Command "cd '$HOOK_CWD'"` |
| Windows/cmd | `start "Shelly" cmd /k "cd /d $HOOK_CWD"` |
| macOS | `do script "cd '$HOOK_CWD'"` |
| Linux | Open terminal with `--working-directory` flag and no command |

## 4. `>>` Auto-Close Mode

**What:** `>>` prefix works like `>` but the terminal closes after the command finishes instead of staying open.

**Detection:** Check if prompt starts with `>>`. Strip both `>` characters to get CMD. Set `KEEP_OPEN=false`.

For single `>`, `KEEP_OPEN=true` (current behavior).

**Platform behavior:**

| Platform | Keep open (>) | Auto-close (>>) |
|----------|---------------|-----------------|
| Windows/wt.exe | `cmd /k` | `cmd /c` |
| Windows/PowerShell | `-NoExit` | (omit `-NoExit`) |
| Windows/cmd | `cmd /k` | `cmd /c` |
| macOS | no `; exit` | append `; exit` |
| Linux | `CMD; exec bash` | just `CMD` (no `exec bash`) |

**Bare `>>`:** Same as bare `>` — opens a terminal in `$HOOK_CWD`. No difference since there's no command to close after.

**Bookmark routing:** `>>` commands still go through bookmark resolution. `>>build` resolves the `build` bookmark, then runs in auto-close mode.

## Prefix Parsing Order

Updated parsing logic in shelly.sh:

1. Check for `>>` prefix first (must come before single `>` check)
2. Check for `>` prefix
3. Check for `/shelly ` prefix
4. Check for bare `/shelly`
5. Otherwise, exit (not a shelly command)

When `>>` is detected, set `KEEP_OPEN=false`. When `>` is detected, set `KEEP_OPEN=true`.

## Changes Summary

All changes are in `scripts/shelly.sh`. No new files.

- **Lines 19-38 (prefix detection + empty command):** Add `>>` detection before `>`, set `KEEP_OPEN` flag, change empty-CMD behavior to open terminal instead of showing usage
- **Lines 96-134 (terminal launch):** Add `$HOOK_CWD` to all platform commands, add echo prefix, add title, use `KEEP_OPEN` to choose between persistent/auto-close terminal modes
- **Line 137 (response):** Update bare-`>` response message
