# Terminal Alias Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional per-command terminal emulator selection via `>!alias` syntax, purely additive with zero changes to existing behavior.

**Architecture:** A `TERMINAL_ALIAS` variable is extracted from CMD after prefix matching but before bookmark/template processing. Inline capture and external terminal dispatch check this variable — if set, dispatch to the alias; if empty, fall through to existing logic untouched.

**Tech Stack:** Bash (scripts/shelly.sh), Markdown (README.md)

---

### Task 1: Parse `!alias` from CMD

**Files:**
- Modify: `scripts/shelly.sh:43` (insert after whitespace trim, before bookmark routing)

- [ ] **Step 1: Add alias extraction after whitespace trim**

Insert the following block in `scripts/shelly.sh` immediately after line 43 (`CMD=$(printf '%s' "$CMD" | sed 's/^[[:space:]]*//')`) and before line 45 (`if [ -n "$CMD" ]; then`):

```bash
# Extract terminal alias (!alias) if present
TERMINAL_ALIAS=""
if [ -n "$CMD" ] && [ "${CMD#!}" != "$CMD" ]; then
  ALIAS_PART="${CMD#!}"
  TERMINAL_ALIAS=$(printf '%s' "$ALIAS_PART" | cut -d' ' -f1)
  TERMINAL_ALIAS=$(printf '%s' "$TERMINAL_ALIAS" | tr '[:upper:]' '[:lower:]')
  CMD=$(printf '%s' "$ALIAS_PART" | sed "s/^[^ ]*[[:space:]]*//" )
fi
```

This extracts the alias, lowercases it for case-insensitive matching, and strips it from CMD so downstream bookmark routing and template substitution see a clean command.

- [ ] **Step 2: Verify parsing doesn't break existing commands**

Test manually in Claude Code:
- `>echo hello` — should open terminal and run echo (no regression)
- `>` — should open bare terminal (no regression)
- `>>echo hello` — should capture output inline (no regression)
- `>+` — should list bookmarks (no regression)

- [ ] **Step 3: Commit**

```bash
git add scripts/shelly.sh
git commit -m "feat(shelly): add terminal alias parsing from >!alias syntax"
```

---

### Task 2: Inline capture mode alias dispatch

**Files:**
- Modify: `scripts/shelly.sh:110-132` (inline capture block)

- [ ] **Step 1: Add SHELL_CMD variable and alias-aware INLINE_NAME**

Replace the inline capture block (lines 110-132). The existing block starts with `if [ "$KEEP_OPEN" = false ] && [ -n "$CMD" ]; then` and ends just before `# Build window title`. Replace with:

```bash
# For auto-close (>>), run locally and capture output instead of opening a terminal
if [ "$KEEP_OPEN" = false ] && [ -n "$CMD" ]; then
  SHELL_CMD="bash -c"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      INLINE_NAME="Git Bash"
      case "$TERMINAL_ALIAS" in
        cmd)  INLINE_NAME="Command Prompt"; SHELL_CMD="cmd.exe /c" ;;
        ps)   INLINE_NAME="PowerShell"; SHELL_CMD="powershell.exe -Command" ;;
        wt)   INLINE_NAME="Windows Terminal" ;;
      esac
      ;;
    Darwin)
      INLINE_NAME="Bash"
      case "$TERMINAL_ALIAS" in
        terminal) INLINE_NAME="Terminal" ;;
        iterm)    INLINE_NAME="iTerm2" ;;
      esac
      ;;
    *)
      INLINE_NAME="Bash"
      case "$TERMINAL_ALIAS" in
        gnome)   INLINE_NAME="GNOME Terminal" ;;
        konsole) INLINE_NAME="Konsole" ;;
        xfce)    INLINE_NAME="Xfce Terminal" ;;
        xterm)   INLINE_NAME="XTerm" ;;
      esac
      ;;
  esac
  SHELLY_TIMEOUT="${SHELLY_TIMEOUT:-10}"
  JSON_CMD=$(printf '%s' "$CMD" | sed 's/[\\]/\\\\/g; s/"/\\"/g')
  if command -v timeout >/dev/null 2>&1; then
    CAPTURE=$(cd "$HOOK_CWD" 2>/dev/null && timeout "$SHELLY_TIMEOUT" $SHELL_CMD "$CMD" 2>&1) || true
  else
    # macOS fallback: use perl one-liner for timeout
    CAPTURE=$(cd "$HOOK_CWD" 2>/dev/null && perl -e "alarm $SHELLY_TIMEOUT; exec @ARGV" $SHELL_CMD "$CMD" 2>&1) || true
  fi
  if [ -n "$CAPTURE" ]; then
    JSON_CWD=$(printf '%s' "$HOOK_CWD" | sed 's/[\\]/\\\\/g; s/"/\\"/g')
    JSON_CAPTURE=$(printf '%s' "$CAPTURE" | sed 's/[\\]/\\\\/g; s/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    printf '{"decision":"block","reason":"[Claude Loves Shelly - %s]\\n%s> %s\\n%s"}\n' "$INLINE_NAME" "$JSON_CWD" "$JSON_CMD" "$JSON_CAPTURE"
  else
    JSON_CWD=$(printf '%s' "$HOOK_CWD" | sed 's/[\\]/\\\\/g; s/"/\\"/g')
    printf '{"decision":"block","reason":"[Claude Loves Shelly - %s]\\n%s> %s\\n(no output)"}\n' "$INLINE_NAME" "$JSON_CWD" "$JSON_CMD"
  fi
  exit 0
fi
```

Key changes:
- Added `SHELL_CMD` variable, defaults to `bash -c`
- Windows `cmd` alias uses `cmd.exe /c`, `ps` alias uses `powershell.exe -Command`
- macOS/Linux aliases only change `INLINE_NAME` label (all use `bash -c`)
- `$SHELL_CMD` is intentionally unquoted so word splitting gives correct args (`bash` `-c` or `cmd.exe` `/c`)
- When `TERMINAL_ALIAS` is empty, all `case` statements fall through to default — no change to existing behavior

- [ ] **Step 2: Verify inline capture still works**

Test manually:
- `>>echo hello` — should show "Git Bash" label and output "hello" (no regression)
- `>>!cmd echo hello` — should show "Command Prompt" label (Windows only)
- `>>!ps echo hello` — should show "PowerShell" label (Windows only)

- [ ] **Step 3: Commit**

```bash
git add scripts/shelly.sh
git commit -m "feat(shelly): add terminal alias support for inline capture mode"
```

---

### Task 3: Windows external terminal alias dispatch

**Files:**
- Modify: `scripts/shelly.sh:144-176` (Windows case block)

- [ ] **Step 1: Wrap existing Windows cascade in alias check**

Replace the Windows case block content. Currently the block starts at `MINGW*|MSYS*|CYGWIN*)` (line 144) and ends at `;;` (line 177). Replace the content between `MINGW*|MSYS*|CYGWIN*)` and its `;;` with:

```bash
    if [ -n "$TERMINAL_ALIAS" ]; then
      case "$TERMINAL_ALIAS" in
        wt)
          if ! command -v wt.exe >/dev/null 2>&1; then
            printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''wt'\'' not found. Install Windows Terminal."}\n'
            exit 0
          fi
          TERMINAL_NAME="Windows Terminal"
          if [ -n "$CMD" ]; then
            MSYS_NO_PATHCONV=1 wt.exe new-tab --title "$TITLE" --startingDirectory "$HOOK_CWD" powershell -NoExit -Command "Write-Host 'PS ${HOOK_CWD}> ${CMD}'\; ${CMD}\; Write-Host ''" 2>/dev/null &
          else
            MSYS_NO_PATHCONV=1 wt.exe new-tab --title "$TITLE" --startingDirectory "$HOOK_CWD" 2>/dev/null &
          fi
          ;;
        ps)
          if ! command -v powershell.exe >/dev/null 2>&1; then
            printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''ps'\'' not found. Install PowerShell."}\n'
            exit 0
          fi
          TERMINAL_NAME="PowerShell"
          if [ -n "$CMD" ]; then
            BATCH="$TEMP/shelly_$$.ps1"
            printf 'Set-Location "%s"\r\nWrite-Host "PS %s> %s"\r\n%s\r\nWrite-Host ""\r\n' "$HOOK_CWD" "$HOOK_CWD" "$CMD" "$CMD" > "$BATCH"
            start powershell.exe -NoExit -ExecutionPolicy Bypass -File "$BATCH" >/dev/null 2>&1 &
          else
            start powershell.exe -NoExit -Command "Set-Location '$HOOK_CWD'" >/dev/null 2>&1 &
          fi
          ;;
        cmd)
          TERMINAL_NAME="Command Prompt"
          if [ -n "$CMD" ]; then
            BATCH="$TEMP/shelly_$$.bat"
            printf '@echo off\r\ncd /d "%s"\r\necho %s^>%s\r\n%s\r\necho.\r\ncmd /k\r\n' "$HOOK_CWD" "$HOOK_CWD" "$CMD" "$CMD" > "$BATCH"
            start "$BATCH" >/dev/null 2>&1 &
          else
            BATCH="$TEMP/shelly_$$.bat"
            printf '@echo off\r\ncd /d "%s"\r\ncmd /k\r\n' "$HOOK_CWD" > "$BATCH"
            start "$BATCH" >/dev/null 2>&1 &
          fi
          ;;
        *)
          printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''%s'\'' not available on this platform. Available: wt, ps, cmd"}\n' "$TERMINAL_ALIAS"
          exit 0
          ;;
      esac
    else
      if command -v wt.exe >/dev/null 2>&1; then
        TERMINAL_NAME="Windows Terminal"
        if [ -n "$CMD" ]; then
          MSYS_NO_PATHCONV=1 wt.exe new-tab --title "$TITLE" --startingDirectory "$HOOK_CWD" powershell -NoExit -Command "Write-Host 'PS ${HOOK_CWD}> ${CMD}'\; ${CMD}\; Write-Host ''" 2>/dev/null &
        else
          MSYS_NO_PATHCONV=1 wt.exe new-tab --title "$TITLE" --startingDirectory "$HOOK_CWD" 2>/dev/null &
        fi
      elif command -v powershell.exe >/dev/null 2>&1; then
        TERMINAL_NAME="PowerShell"
        if [ -n "$CMD" ]; then
          BATCH="$TEMP/shelly_$$.ps1"
          printf 'Set-Location "%s"\r\nWrite-Host "PS %s> %s"\r\n%s\r\nWrite-Host ""\r\n' "$HOOK_CWD" "$HOOK_CWD" "$CMD" "$CMD" > "$BATCH"
          start powershell.exe -NoExit -ExecutionPolicy Bypass -File "$BATCH" >/dev/null 2>&1 &

        else
          start powershell.exe -NoExit -Command "Set-Location '$HOOK_CWD'" >/dev/null 2>&1 &

        fi
      else
        TERMINAL_NAME="Command Prompt"
        if [ -n "$CMD" ]; then
          BATCH="$TEMP/shelly_$$.bat"
          printf '@echo off\r\ncd /d "%s"\r\necho %s^>%s\r\n%s\r\necho.\r\ncmd /k\r\n' "$HOOK_CWD" "$HOOK_CWD" "$CMD" "$CMD" > "$BATCH"
          start "$BATCH" >/dev/null 2>&1 &

        else
          BATCH="$TEMP/shelly_$$.bat"
          printf '@echo off\r\ncd /d "%s"\r\ncmd /k\r\n' "$HOOK_CWD" > "$BATCH"
          start "$BATCH" >/dev/null 2>&1 &

        fi
      fi
    fi
```

The `else` branch contains the **exact existing code** — untouched. The `if [ -n "$TERMINAL_ALIAS" ]` branch adds the new alias dispatch with per-alias `command -v` validation and platform-specific error messages.

- [ ] **Step 2: Verify no regression on default behavior**

Test manually on Windows:
- `>echo hello` — should auto-detect terminal (same as before)
- `>` — should open bare terminal (same as before)
- `>!cmd echo hello` — should open Command Prompt with echo
- `>!cmd` — should open bare Command Prompt
- `>!ps echo hello` — should open PowerShell with echo
- `>!wt echo hello` — should open Windows Terminal with echo
- `>!foo echo hello` — should show error about invalid alias

- [ ] **Step 3: Commit**

```bash
git add scripts/shelly.sh
git commit -m "feat(shelly): add terminal alias dispatch for Windows"
```

---

### Task 4: macOS external terminal alias dispatch

**Files:**
- Modify: `scripts/shelly.sh` (Darwin case block)

- [ ] **Step 1: Wrap existing Darwin block in alias check**

Replace the content between `Darwin)` and its `;;` with:

```bash
    if [ -n "$TERMINAL_ALIAS" ]; then
      case "$TERMINAL_ALIAS" in
        terminal)
          TERMINAL_NAME="Terminal"
          if [ -n "$CMD" ]; then
            ESCAPED=$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
            ESCAPED_TITLE=$(printf '%s' "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')
            SCRIPT_CMD="printf '\\033]0;${ESCAPED_TITLE}\\007' && cd '${HOOK_CWD}' && echo '${HOOK_CWD}\$ ${ESCAPED}' && ${ESCAPED} && echo"
          else
            SCRIPT_CMD="cd '${HOOK_CWD}'"
          fi
          osascript -e "tell application \"Terminal\"" \
                    -e "activate" \
                    -e "do script \"${SCRIPT_CMD}\"" \
                    -e "end tell" 2>/dev/null
          ;;
        iterm)
          if ! osascript -e 'id of application "iTerm2"' >/dev/null 2>&1; then
            printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''iterm'\'' not found. Install iTerm2."}\n'
            exit 0
          fi
          TERMINAL_NAME="iTerm2"
          if [ -n "$CMD" ]; then
            ESCAPED=$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
            SCRIPT_CMD="cd '${HOOK_CWD}' && echo '${HOOK_CWD}\$ ${ESCAPED}' && ${ESCAPED} && echo"
          else
            SCRIPT_CMD="cd '${HOOK_CWD}'"
          fi
          osascript -e "tell application \"iTerm2\"" \
                    -e "activate" \
                    -e "create window with default profile" \
                    -e "tell current session of current window" \
                    -e "write text \"${SCRIPT_CMD}\"" \
                    -e "end tell" \
                    -e "end tell" 2>/dev/null
          ;;
        *)
          printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''%s'\'' not available on this platform. Available: terminal, iterm"}\n' "$TERMINAL_ALIAS"
          exit 0
          ;;
      esac
    else
      TERMINAL_NAME="Terminal"
      if [ -n "$CMD" ]; then
        ESCAPED=$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
        ESCAPED_TITLE=$(printf '%s' "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')
        SCRIPT_CMD="printf '\\033]0;${ESCAPED_TITLE}\\007' && cd '${HOOK_CWD}' && echo '${HOOK_CWD}\$ ${ESCAPED}' && ${ESCAPED} && echo"
      else
        SCRIPT_CMD="cd '${HOOK_CWD}'"
      fi
      osascript -e "tell application \"Terminal\"" \
                -e "activate" \
                -e "do script \"${SCRIPT_CMD}\"" \
                -e "end tell" 2>/dev/null
    fi
```

The `else` branch is the **exact existing Terminal.app code** — untouched. The `terminal` alias duplicates it for explicit selection. The `iterm` alias uses iTerm2's AppleScript dictionary: `create window with default profile` opens a new window, then `write text` sends the command to the session. iTerm2 existence is checked via `osascript -e 'id of application "iTerm2"'`.

- [ ] **Step 2: Verify no regression**

Test on macOS (if available):
- `>echo hello` — should open Terminal.app (same as before)
- `>!terminal echo hello` — should open Terminal.app explicitly
- `>!iterm echo hello` — should open iTerm2 (if installed)
- `>!foo` — should show error about invalid alias

- [ ] **Step 3: Commit**

```bash
git add scripts/shelly.sh
git commit -m "feat(shelly): add terminal alias dispatch for macOS"
```

---

### Task 5: Linux external terminal alias dispatch

**Files:**
- Modify: `scripts/shelly.sh` (Linux case block)

- [ ] **Step 1: Wrap existing Linux block in alias check**

Replace the content between `Linux)` and its `;;` with:

```bash
    if [ -n "$TERMINAL_ALIAS" ]; then
      if [ -n "$CMD" ]; then
        BASH_CMD="echo '$HOOK_CWD\$ $CMD' && $CMD && echo; exec bash"
      fi
      case "$TERMINAL_ALIAS" in
        gnome)
          if ! command -v gnome-terminal >/dev/null 2>&1; then
            printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''gnome'\'' not found. Install gnome-terminal."}\n'
            exit 0
          fi
          TERMINAL_NAME="GNOME Terminal"
          if [ -n "$CMD" ]; then
            nohup gnome-terminal --title="$TITLE" --working-directory="$HOOK_CWD" -- bash -c "$BASH_CMD" >/dev/null 2>&1 &
          else
            nohup gnome-terminal --title="$TITLE" --working-directory="$HOOK_CWD" >/dev/null 2>&1 &
          fi
          ;;
        konsole)
          if ! command -v konsole >/dev/null 2>&1; then
            printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''konsole'\'' not found. Install konsole."}\n'
            exit 0
          fi
          TERMINAL_NAME="Konsole"
          if [ -n "$CMD" ]; then
            nohup konsole -p tabtitle="$TITLE" --workdir "$HOOK_CWD" -e bash -c "$BASH_CMD" >/dev/null 2>&1 &
          else
            nohup konsole -p tabtitle="$TITLE" --workdir "$HOOK_CWD" >/dev/null 2>&1 &
          fi
          ;;
        xfce)
          if ! command -v xfce4-terminal >/dev/null 2>&1; then
            printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''xfce'\'' not found. Install xfce4-terminal."}\n'
            exit 0
          fi
          TERMINAL_NAME="Xfce Terminal"
          if [ -n "$CMD" ]; then
            nohup xfce4-terminal --title="$TITLE" --working-directory="$HOOK_CWD" -e "bash -c \"$BASH_CMD\"" >/dev/null 2>&1 &
          else
            nohup xfce4-terminal --title="$TITLE" --working-directory="$HOOK_CWD" >/dev/null 2>&1 &
          fi
          ;;
        xterm)
          if ! command -v xterm >/dev/null 2>&1; then
            printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''xterm'\'' not found. Install xterm."}\n'
            exit 0
          fi
          TERMINAL_NAME="XTerm"
          if [ -n "$CMD" ]; then
            nohup xterm -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && $BASH_CMD" >/dev/null 2>&1 &
          else
            nohup xterm -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && exec bash" >/dev/null 2>&1 &
          fi
          ;;
        *)
          printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nTerminal '\''%s'\'' not available on this platform. Available: gnome, konsole, xfce, xterm"}\n' "$TERMINAL_ALIAS"
          exit 0
          ;;
      esac
    else
      if [ -n "$CMD" ]; then
        BASH_CMD="echo '$HOOK_CWD\$ $CMD' && $CMD && echo; exec bash"
      fi
      if command -v x-terminal-emulator >/dev/null 2>&1; then
        TERMINAL_NAME="Terminal"
        if [ -n "$CMD" ]; then
          nohup x-terminal-emulator -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && $BASH_CMD" >/dev/null 2>&1 &
        else
          nohup x-terminal-emulator -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && exec bash" >/dev/null 2>&1 &
        fi
      elif command -v gnome-terminal >/dev/null 2>&1; then
        TERMINAL_NAME="GNOME Terminal"
        if [ -n "$CMD" ]; then
          nohup gnome-terminal --title="$TITLE" --working-directory="$HOOK_CWD" -- bash -c "$BASH_CMD" >/dev/null 2>&1 &
        else
          nohup gnome-terminal --title="$TITLE" --working-directory="$HOOK_CWD" >/dev/null 2>&1 &
        fi
      elif command -v konsole >/dev/null 2>&1; then
        TERMINAL_NAME="Konsole"
        if [ -n "$CMD" ]; then
          nohup konsole -p tabtitle="$TITLE" --workdir "$HOOK_CWD" -e bash -c "$BASH_CMD" >/dev/null 2>&1 &
        else
          nohup konsole -p tabtitle="$TITLE" --workdir "$HOOK_CWD" >/dev/null 2>&1 &
        fi
      elif command -v xfce4-terminal >/dev/null 2>&1; then
        TERMINAL_NAME="Xfce Terminal"
        if [ -n "$CMD" ]; then
          nohup xfce4-terminal --title="$TITLE" --working-directory="$HOOK_CWD" -e "bash -c \"$BASH_CMD\"" >/dev/null 2>&1 &
        else
          nohup xfce4-terminal --title="$TITLE" --working-directory="$HOOK_CWD" >/dev/null 2>&1 &
        fi
      elif command -v xterm >/dev/null 2>&1; then
        TERMINAL_NAME="XTerm"
        if [ -n "$CMD" ]; then
          nohup xterm -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && $BASH_CMD" >/dev/null 2>&1 &
        else
          nohup xterm -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && exec bash" >/dev/null 2>&1 &
        fi
      else
        printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nNo terminal emulator found. Install x-terminal-emulator, gnome-terminal, konsole, xfce4-terminal, or xterm."}\n'
        exit 0
      fi
    fi
```

The `else` branch is the **exact existing Linux cascade** — untouched. The alias dispatch skips `x-terminal-emulator` (system default) since the user is explicitly choosing a terminal. Each alias checks `command -v` before use.

- [ ] **Step 2: Verify no regression**

Test on Linux (if available):
- `>echo hello` — should auto-detect terminal (same as before)
- `>!gnome echo hello` — should open GNOME Terminal (if installed)
- `>!foo` — should show error about invalid alias

- [ ] **Step 3: Commit**

```bash
git add scripts/shelly.sh
git commit -m "feat(shelly): add terminal alias dispatch for Linux"
```

---

### Task 6: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add alias rows to cheatsheet**

In the cheatsheet table (after the `>name` row and before the `/shelly command` row), add:

```markdown
| `>!alias command` | Run command in specific terminal |
| `>>!alias command` | Run and capture output using specific terminal's shell |
```

- [ ] **Step 2: Add Terminal Selection section**

Insert a new section after "Template Variables" (after line 118) and before "How it works" (line 119):

```markdown
## Terminal Selection

Override the default terminal with `!alias` after the `>` prefix:

```
>!cmd echo hello
>>!ps git status
>!iterm npm test
/shelly !cmd echo hello
/shelly >!ps git status
```

| Platform | Alias | Terminal |
|----------|-------|----------|
| Windows | `wt` | Windows Terminal |
| Windows | `ps` | PowerShell |
| Windows | `cmd` | Command Prompt |
| macOS | `terminal` | Terminal.app |
| macOS | `iterm` | iTerm2 |
| Linux | `gnome` | GNOME Terminal |
| Linux | `konsole` | Konsole |
| Linux | `xfce` | Xfce Terminal |
| Linux | `xterm` | XTerm |

Without `!alias`, Shelly auto-detects the best available terminal (default behavior).
```

- [ ] **Step 3: Add note to "How it works" section**

After the existing first paragraph of "How it works" (line 121: `A UserPromptSubmit hook intercepts prompts starting with...`), add:

```markdown
Use `>!alias` to bypass auto-detection and target a specific terminal (e.g., `>!cmd` for Command Prompt on Windows, `>!iterm` for iTerm2 on macOS).
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add terminal alias selection to README"
```
