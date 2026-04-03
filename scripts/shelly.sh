#!/usr/bin/env bash

# Read hook input from stdin and parse all fields
INPUT=$(cat)
eval "$(printf '%s' "$INPUT" | node -e "
  const d=JSON.parse(require('fs').readFileSync(0,'utf8'));
  const esc=s=>(s||'').replace(/\\\\/g,'\\\\\\\\').replace(/'/g,\"'\\\\''\");
  const m={prompt:'PROMPT',session_id:'SESSION_ID',transcript_path:'TRANSCRIPT_PATH',
           cwd:'CWD',permission_mode:'PERMISSION_MODE',hook_event_name:'EVENT_NAME'};
  Object.entries(m).forEach(([k,v])=>console.log('HOOK_'+v+\"='\"+esc(d[k])+\"'\"));
" 2>/dev/null)" || exit 0

if [ -z "$HOOK_PROMPT" ]; then
  exit 0
fi

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

# Build window title
if [ -n "$CMD" ]; then
  TITLE="Shelly — $CMD"
else
  TITLE="Shelly"
fi

# Detect platform and open external terminal
OS=$(uname -s)
case "$OS" in
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
  *)
    printf '{"decision":"block","reason":"Unsupported platform: %s"}\n' "$OS"
    exit 0
    ;;
esac

if [ -n "$CMD" ]; then
  JSON_CMD=$(printf '%s' "$CMD" | sed 's/[\\]/\\\\/g; s/"/\\"/g')
  printf '{"decision":"block","reason":"Opened external terminal: %s"}\n' "$JSON_CMD"
else
  printf '{"decision":"block","reason":"Opened terminal"}\n'
fi
exit 0
