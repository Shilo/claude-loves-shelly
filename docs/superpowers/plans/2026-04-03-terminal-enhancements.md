# Terminal Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add command echo + window title, working directory, bare `>` terminal open, and `>>` auto-close mode to shelly.sh

**Architecture:** All changes in `scripts/shelly.sh` plus a CLAUDE.md update. Rewrite prefix parsing to detect `>>` before `>` with a `KEEP_OPEN` flag, guard bookmark/template logic for empty commands, build title variable, and update all platform-specific terminal launch blocks with CWD, echo, title, and keep-open/auto-close behavior.

**Tech Stack:** Bash, Windows Terminal (wt.exe), PowerShell, cmd.exe, macOS Terminal.app (osascript), Linux terminal emulators

---

### Task 1: Rewrite shelly.sh

All four features are intertwined in the same file, so this task rewrites the script section by section.

**Files:**
- Modify: `scripts/shelly.sh`

- [ ] **Step 1: Replace prefix detection block (lines 17-38)**

Replace:

```bash
# Case-insensitive prefix matching
LOWER=$(printf '%s' "$HOOK_PROMPT" | tr '[:upper:]' '[:lower:]')
CMD=""

if [ "${HOOK_PROMPT#>}" != "$HOOK_PROMPT" ]; then
  CMD="${HOOK_PROMPT#>}"
elif [ "${LOWER#/shelly }" != "$LOWER" ]; then
  CMD="${HOOK_PROMPT#????????}"
elif [ "$LOWER" = "/shelly" ]; then
  printf '{"decision":"block","reason":"Usage: >[command] or /shelly [command]. Example: >git status"}\n'
  exit 0
else
  exit 0
fi

# Trim leading whitespace
CMD=$(printf '%s' "$CMD" | sed 's/^[[:space:]]*//')

if [ -z "$CMD" ]; then
  printf '{"decision":"block","reason":"Usage: >[command] or /shelly [command]. Example: >git status"}\n'
  exit 0
fi
```

With:

```bash
# Prefix matching — >> must be checked before >
LOWER=$(printf '%s' "$HOOK_PROMPT" | tr '[:upper:]' '[:lower:]')
CMD=""
KEEP_OPEN=true

if [ "${HOOK_PROMPT#>>}" != "$HOOK_PROMPT" ]; then
  CMD="${HOOK_PROMPT#>>}"
  KEEP_OPEN=false
elif [ "${HOOK_PROMPT#>}" != "$HOOK_PROMPT" ]; then
  CMD="${HOOK_PROMPT#>}"
elif [ "${LOWER#/shelly }" != "$LOWER" ]; then
  CMD="${HOOK_PROMPT#????????}"
elif [ "$LOWER" = "/shelly" ]; then
  printf '{"decision":"block","reason":"Usage: >[command] or /shelly [command]. Example: >git status"}\n'
  exit 0
else
  exit 0
fi

# Trim leading whitespace
CMD=$(printf '%s' "$CMD" | sed 's/^[[:space:]]*//')

# Empty CMD after /shelly shows usage; bare > and >> open a terminal
if [ -z "$CMD" ] && [ "${HOOK_PROMPT#>}" = "$HOOK_PROMPT" ]; then
  printf '{"decision":"block","reason":"Usage: >[command] or /shelly [command]. Example: >git status"}\n'
  exit 0
fi
```

- [ ] **Step 2: Wrap bookmark routing + template vars in empty-CMD guard**

Replace the bookmark routing section (lines 40-94 in original, starting at `# Bookmark routing`) by wrapping everything from `# Bookmark routing` through the last template variable substitution in a single guard:

```bash
if [ -n "$CMD" ]; then
  # Bookmark routing
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  BOOKMARKS_SH="$SCRIPT_DIR/bookmarks.sh"

  if [ "${CMD#+}" != "$CMD" ]; then
    # >+ prefix: add, lookup, or list
    PLUS_ARG="${CMD#+}"
    if [ -z "$PLUS_ARG" ]; then
      # Bare >+ : list all bookmarks
      RESULT=$("$BOOKMARKS_SH" list "$PLUGIN_ROOT")
      printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s' "$RESULT" | sed 's/"/\\"/g' | tr '\n' ' ')"
      exit 0
    fi
    BM_NAME=$(printf '%s' "$PLUS_ARG" | sed 's/^[[:space:]]*//' | cut -d' ' -f1)
    BM_CMD=$(printf '%s' "$PLUS_ARG" | sed 's/^[[:space:]]*//' | sed "s/^$BM_NAME[[:space:]]*//" )
    if [ -z "$BM_CMD" ]; then
      # >+name : lookup
      RESULT=$("$BOOKMARKS_SH" add "$PLUGIN_ROOT" "$BM_NAME")
      printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s' "$RESULT" | sed 's/"/\\"/g')"
      exit 0
    else
      # >+name command : save
      RESULT=$("$BOOKMARKS_SH" add "$PLUGIN_ROOT" "$BM_NAME" "$BM_CMD")
      printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s' "$RESULT" | sed 's/"/\\"/g')"
      exit 0
    fi
  elif [ "${CMD#-}" != "$CMD" ]; then
    # >- prefix: remove
    BM_NAME=$(printf '%s' "${CMD#-}" | sed 's/^[[:space:]]*//')
    if [ -z "$BM_NAME" ]; then
      printf '{"decision":"block","reason":"Usage: >-[name]. Example: >-build"}\n'
      exit 0
    fi
    RESULT=$("$BOOKMARKS_SH" remove "$PLUGIN_ROOT" "$BM_NAME")
    printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s' "$RESULT" | sed 's/"/\\"/g')"
    exit 0
  else
    # Check if first word is a bookmark
    FIRST_WORD=$(printf '%s' "$CMD" | cut -d' ' -f1)
    REST=$(printf '%s' "$CMD" | sed "s/^$FIRST_WORD[[:space:]]*//" )
    RESOLVED=$("$BOOKMARKS_SH" resolve "$PLUGIN_ROOT" "$FIRST_WORD" "$REST")
    if [ $? -eq 0 ]; then
      CMD="$RESOLVED"
    fi
  fi

  # Replace template variables with hook input values
  CMD="${CMD//\{prompt\}/$HOOK_PROMPT}"
  CMD="${CMD//\{session_id\}/$HOOK_SESSION_ID}"
  CMD="${CMD//\{transcript_path\}/$HOOK_TRANSCRIPT_PATH}"
  CMD="${CMD//\{cwd\}/$HOOK_CWD}"
  CMD="${CMD//\{permission_mode\}/$HOOK_PERMISSION_MODE}"
  CMD="${CMD//\{hook_event_name\}/$HOOK_EVENT_NAME}"
fi
```

- [ ] **Step 3: Add title variable after the guard block**

Insert after the closing `fi` of the guard block:

```bash
# Build window title
if [ -n "$CMD" ]; then
  TITLE="Shelly — $CMD"
else
  TITLE="Shelly"
fi
```

- [ ] **Step 4: Replace Windows terminal launch block**

Replace the `MINGW*|MSYS*|CYGWIN*)` case with:

```bash
  MINGW*|MSYS*|CYGWIN*)
    if command -v wt.exe >/dev/null 2>&1; then
      if [ -n "$CMD" ]; then
        if [ "$KEEP_OPEN" = true ]; then
          MSYS_NO_PATHCONV=1 wt.exe new-tab --title "$TITLE" --startingDirectory "$HOOK_CWD" cmd /k "echo ^> $CMD && $CMD" 2>/dev/null &
        else
          MSYS_NO_PATHCONV=1 wt.exe new-tab --title "$TITLE" --startingDirectory "$HOOK_CWD" cmd /c "echo ^> $CMD && $CMD" 2>/dev/null &
        fi
      else
        MSYS_NO_PATHCONV=1 wt.exe new-tab --title "$TITLE" --startingDirectory "$HOOK_CWD" 2>/dev/null &
      fi
    elif command -v powershell.exe >/dev/null 2>&1; then
      if [ -n "$CMD" ]; then
        if [ "$KEEP_OPEN" = true ]; then
          cmd.exe /c "start \"$TITLE\" powershell -NoExit -Command \"cd '$HOOK_CWD'; Write-Host '> $CMD'; $CMD\"" 2>/dev/null &
        else
          cmd.exe /c "start \"$TITLE\" powershell -Command \"cd '$HOOK_CWD'; Write-Host '> $CMD'; $CMD\"" 2>/dev/null &
        fi
      else
        cmd.exe /c "start \"$TITLE\" powershell -NoExit -Command \"cd '$HOOK_CWD'\"" 2>/dev/null &
      fi
    else
      if [ -n "$CMD" ]; then
        if [ "$KEEP_OPEN" = true ]; then
          cmd.exe /c "start \"$TITLE\" cmd /k \"cd /d $HOOK_CWD && echo ^> $CMD && $CMD\"" 2>/dev/null &
        else
          cmd.exe /c "start \"$TITLE\" cmd /c \"cd /d $HOOK_CWD && echo ^> $CMD && $CMD\"" 2>/dev/null &
        fi
      else
        cmd.exe /c "start \"$TITLE\" cmd /k \"cd /d $HOOK_CWD\"" 2>/dev/null &
      fi
    fi
    ;;
```

- [ ] **Step 5: Replace macOS terminal launch block**

Replace the `Darwin)` case with:

```bash
  Darwin)
    if [ -n "$CMD" ]; then
      ESCAPED=$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
      ESCAPED_TITLE=$(printf '%s' "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')
      SCRIPT_CMD="printf '\\033]0;${ESCAPED_TITLE}\\007' && cd '${HOOK_CWD}' && echo '> ${ESCAPED}' && ${ESCAPED}"
      if [ "$KEEP_OPEN" = false ]; then
        SCRIPT_CMD="${SCRIPT_CMD}; exit"
      fi
    else
      SCRIPT_CMD="cd '${HOOK_CWD}'"
    fi
    osascript -e "tell application \"Terminal\"" \
              -e "activate" \
              -e "do script \"${SCRIPT_CMD}\"" \
              -e "end tell" 2>/dev/null
    ;;
```

Note: macOS title is set via ANSI escape sequence (`\033]0;TITLE\007`) which works in Terminal.app and iTerm2.

- [ ] **Step 6: Replace Linux terminal launch block**

Replace the `Linux)` case with:

```bash
  Linux)
    if [ -n "$CMD" ]; then
      if [ "$KEEP_OPEN" = true ]; then
        BASH_CMD="echo '> $CMD' && $CMD; exec bash"
      else
        BASH_CMD="echo '> $CMD' && $CMD"
      fi
    fi
    if command -v x-terminal-emulator >/dev/null 2>&1; then
      if [ -n "$CMD" ]; then
        nohup x-terminal-emulator -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && $BASH_CMD" >/dev/null 2>&1 &
      else
        nohup x-terminal-emulator -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && exec bash" >/dev/null 2>&1 &
      fi
    elif command -v gnome-terminal >/dev/null 2>&1; then
      if [ -n "$CMD" ]; then
        nohup gnome-terminal --title="$TITLE" --working-directory="$HOOK_CWD" -- bash -c "$BASH_CMD" >/dev/null 2>&1 &
      else
        nohup gnome-terminal --title="$TITLE" --working-directory="$HOOK_CWD" >/dev/null 2>&1 &
      fi
    elif command -v konsole >/dev/null 2>&1; then
      if [ -n "$CMD" ]; then
        nohup konsole -p tabtitle="$TITLE" --workdir "$HOOK_CWD" -e bash -c "$BASH_CMD" >/dev/null 2>&1 &
      else
        nohup konsole -p tabtitle="$TITLE" --workdir "$HOOK_CWD" >/dev/null 2>&1 &
      fi
    elif command -v xfce4-terminal >/dev/null 2>&1; then
      if [ -n "$CMD" ]; then
        nohup xfce4-terminal --title="$TITLE" --working-directory="$HOOK_CWD" -e "bash -c \"$BASH_CMD\"" >/dev/null 2>&1 &
      else
        nohup xfce4-terminal --title="$TITLE" --working-directory="$HOOK_CWD" >/dev/null 2>&1 &
      fi
    elif command -v xterm >/dev/null 2>&1; then
      if [ -n "$CMD" ]; then
        nohup xterm -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && $BASH_CMD" >/dev/null 2>&1 &
      else
        nohup xterm -T "$TITLE" -e bash -c "cd '$HOOK_CWD' && exec bash" >/dev/null 2>&1 &
      fi
    else
      printf '{"decision":"block","reason":"No terminal emulator found. Install x-terminal-emulator, gnome-terminal, konsole, xfce4-terminal, or xterm."}\n'
      exit 0
    fi
    ;;
```

- [ ] **Step 7: Replace response message (end of file)**

Replace:

```bash
JSON_CMD=$(printf '%s' "$CMD" | sed 's/[\\]/\\\\/g; s/"/\\"/g')
printf '{"decision":"block","reason":"Opened external terminal: %s"}\n' "$JSON_CMD"
exit 0
```

With:

```bash
if [ -n "$CMD" ]; then
  JSON_CMD=$(printf '%s' "$CMD" | sed 's/[\\]/\\\\/g; s/"/\\"/g')
  printf '{"decision":"block","reason":"Opened external terminal: %s"}\n' "$JSON_CMD"
else
  printf '{"decision":"block","reason":"Opened terminal"}\n'
fi
exit 0
```

- [ ] **Step 8: Commit**

```bash
git add scripts/shelly.sh
git commit -m "feat: add echo, cwd, bare > open, and >> auto-close to terminal launch"
```

---

### Task 2: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update project description**

Replace:

```
Claude plugin to open commands in an external terminal window with `>` prefix or `/shelly` command. Supports saved command bookmarks.
```

With:

```
Claude plugin to open commands in an external terminal window with `>` prefix or `/shelly` command. Use `>>` to auto-close the terminal after the command finishes. Type bare `>` to open a terminal in the current directory. Supports saved command bookmarks.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with >> and bare > features"
```

---

### Task 3: Manual testing

Run these tests in Claude Code to verify all features work:

- [ ] **Test 1: `>echo hello`** — Opens terminal in Claude's CWD, prints `> echo hello` then `hello`, title shows `Shelly — echo hello`, terminal stays open
- [ ] **Test 2: `>>echo hello`** — Same as test 1 but terminal closes after command finishes
- [ ] **Test 3: `>`** — Opens a blank terminal in Claude's CWD, title shows `Shelly`, no echo
- [ ] **Test 4: `>>`** — Same as test 3 (bare >> = bare >)
- [ ] **Test 5: `/shelly echo hello`** — Opens terminal with echo, CWD, title, stays open
- [ ] **Test 6: `/shelly`** — Shows usage message (unchanged behavior)
- [ ] **Test 7: `>+test echo hello` then `>>test`** — Bookmark saves, then auto-close resolves and runs it
