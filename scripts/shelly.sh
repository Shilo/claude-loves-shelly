#!/usr/bin/env bash

# Read hook input from stdin and parse all fields
INPUT=$(cat)
eval "$(printf '%s' "$INPUT" | node -e "
  const d=JSON.parse(require('fs').readFileSync(0,'utf8'));
  const esc=s=>(s||'').replace(/'/g,\"'\\\\''\");
  const m={prompt:'PROMPT',session_id:'SESSION_ID',transcript_path:'TRANSCRIPT_PATH',
           cwd:'CWD',permission_mode:'PERMISSION_MODE',hook_event_name:'EVENT_NAME'};
  Object.entries(m).forEach(([k,v])=>console.log('HOOK_'+v+\"='\"+esc(d[k])+\"'\"));
" 2>/dev/null)" || exit 0

if [ -z "$HOOK_PROMPT" ]; then
  exit 0
fi

ORIGINAL_PROMPT="$HOOK_PROMPT"

# Normalize /shelly to > prefix so all paths share the same logic
LOWER=$(printf '%s' "$HOOK_PROMPT" | tr '[:upper:]' '[:lower:]')
if [ "${LOWER#/shelly }" != "$LOWER" ]; then
  REST="${HOOK_PROMPT#????????}"
  # /shelly = >, so /shelly > = >>, /shelly >> = >>>  (>>> treated as >>)
  HOOK_PROMPT=">$REST"
elif [ "$LOWER" = "/shelly" ]; then
  HOOK_PROMPT=">"
fi

# Prefix matching — >> must be checked before >
CMD=""
KEEP_OPEN=true

if [ "${HOOK_PROMPT#>>}" != "$HOOK_PROMPT" ]; then
  CMD=$(printf '%s' "${HOOK_PROMPT#>>}" | sed 's/^>*//')
  KEEP_OPEN=false
elif [ "${HOOK_PROMPT#>}" != "$HOOK_PROMPT" ]; then
  CMD="${HOOK_PROMPT#>}"
else
  exit 0
fi

# Trim leading whitespace
CMD=$(printf '%s' "$CMD" | sed 's/^[[:space:]]*//')

# Extract terminal alias (!alias) if present
TERMINAL_ALIAS=""
if [ -n "$CMD" ] && [ "${CMD#!}" != "$CMD" ]; then
  ALIAS_PART="${CMD#!}"
  TERMINAL_ALIAS=$(printf '%s' "$ALIAS_PART" | cut -d' ' -f1)
  TERMINAL_ALIAS=$(printf '%s' "$TERMINAL_ALIAS" | tr '[:upper:]' '[:lower:]')
  CMD=$(printf '%s' "$ALIAS_PART" | sed "s/^[^ ]*[[:space:]]*//" )
fi

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
      printf '{"decision":"block","reason":"[Claude Loves Shelly - Bookmarks]\\n%s"}\n' "$(printf '%s' "$RESULT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')"
      exit 0
    fi
    BM_NAME=$(printf '%s' "$PLUS_ARG" | sed 's/^[[:space:]]*//' | cut -d' ' -f1)
    BM_CMD=$(printf '%s' "$PLUS_ARG" | sed 's/^[[:space:]]*//' | sed "s/^$BM_NAME[[:space:]]*//" )
    if [ -z "$BM_CMD" ]; then
      # >+name : lookup
      RESULT=$("$BOOKMARKS_SH" add "$PLUGIN_ROOT" "$BM_NAME")
      printf '{"decision":"block","reason":"[Claude Loves Shelly - Bookmarks]\\n%s"}\n' "$(printf '%s' "$RESULT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')"
      exit 0
    else
      # >+name command : save
      RESULT=$("$BOOKMARKS_SH" add "$PLUGIN_ROOT" "$BM_NAME" "$BM_CMD")
      printf '{"decision":"block","reason":"[Claude Loves Shelly - Bookmarks]\\n%s"}\n' "$(printf '%s' "$RESULT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')"
      exit 0
    fi
  elif [ "${CMD#-}" != "$CMD" ]; then
    # >- prefix: remove
    BM_NAME=$(printf '%s' "${CMD#-}" | sed 's/^[[:space:]]*//')
    if [ -z "$BM_NAME" ]; then
      printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nUsage: >-[name]. Example: >-build"}\n'
      exit 0
    fi
    RESULT=$("$BOOKMARKS_SH" remove "$PLUGIN_ROOT" "$BM_NAME")
    printf '{"decision":"block","reason":"[Claude Loves Shelly - Bookmarks]\\n%s"}\n' "$(printf '%s' "$RESULT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')"
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

  # Replace template variables with hook input values (shell-escaped for safe use)
  OS_CHECK=$(uname -s)
  case "$OS_CHECK" in
    MINGW*|MSYS*|CYGWIN*)
      shell_escape() { printf '"%s"' "$(printf '%s' "$1" | sed 's/"/\\"/g')"; } ;;
    *)
      shell_escape() { printf '%s' "$1" | sed "s/'/'\\\\''/g; 1s/^/'/; \$s/\$/'/"; } ;;
  esac
  CMD="${CMD//\{prompt\}/$(shell_escape "$ORIGINAL_PROMPT")}"
  CMD="${CMD//\{session_id\}/$(shell_escape "$HOOK_SESSION_ID")}"
  CMD="${CMD//\{transcript_path\}/$(shell_escape "$HOOK_TRANSCRIPT_PATH")}"
  CMD="${CMD//\{cwd\}/$(shell_escape "$HOOK_CWD")}"
  CMD="${CMD//\{permission_mode\}/$(shell_escape "$HOOK_PERMISSION_MODE")}"
  CMD="${CMD//\{hook_event_name\}/$(shell_escape "$HOOK_EVENT_NAME")}"
fi

# For auto-close (>>), run locally and capture output instead of opening a terminal
if [ "$KEEP_OPEN" = false ] && [ -n "$CMD" ]; then
  # Alias overrides: cmd/ps change the shell used for execution;
  # emulator aliases (wt, iterm, gnome, etc.) only change the display label
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

# Build window title
if [ -n "$CMD" ]; then
  TITLE="Shelly - $CMD"
else
  TITLE="Shelly"
fi

# Detect platform and open external terminal
OS=$(uname -s)
case "$OS" in
  MINGW*|MSYS*|CYGWIN*)
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
    ;;
  Darwin)
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
    ;;
  Linux)
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
    ;;
  *)
    printf '{"decision":"block","reason":"[Claude Loves Shelly - Error]\\nUnsupported platform: %s"}\n' "$OS"
    exit 0
    ;;
esac

if [ -n "$CMD" ]; then
  JSON_CMD=$(printf '%s' "$CMD" | sed 's/[\\]/\\\\/g; s/"/\\"/g')
  printf '{"decision":"block","reason":"[Claude Loves Shelly - %s]\\nOpened external terminal: %s"}\n' "$TERMINAL_NAME" "$JSON_CMD"
else
  printf '{"decision":"block","reason":"[Claude Loves Shelly - %s]\\nOpened terminal"}\n' "$TERMINAL_NAME"
fi
exit 0
