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

# Case-insensitive prefix matching
LOWER=$(printf '%s' "$HOOK_PROMPT" | tr '[:upper:]' '[:lower:]')
CMD=""

if [ "${HOOK_PROMPT#!}" != "$HOOK_PROMPT" ]; then
  CMD="${HOOK_PROMPT#!}"
elif [ "${LOWER#/shelly }" != "$LOWER" ]; then
  CMD="${HOOK_PROMPT#????????}"
elif [ "$LOWER" = "/shelly" ]; then
  printf '{"decision":"block","reason":"Usage: !<command> or /shelly <command>"}\n'
  exit 0
else
  exit 0
fi

# Trim leading whitespace
CMD=$(printf '%s' "$CMD" | sed 's/^[[:space:]]*//')

if [ -z "$CMD" ]; then
  printf '{"decision":"block","reason":"Usage: !<command> or /shelly <command>"}\n'
  exit 0
fi

# Replace template variables with hook input values
CMD="${CMD//\{prompt\}/$HOOK_PROMPT}"
CMD="${CMD//\{session_id\}/$HOOK_SESSION_ID}"
CMD="${CMD//\{transcript_path\}/$HOOK_TRANSCRIPT_PATH}"
CMD="${CMD//\{cwd\}/$HOOK_CWD}"
CMD="${CMD//\{permission_mode\}/$HOOK_PERMISSION_MODE}"
CMD="${CMD//\{hook_event_name\}/$HOOK_EVENT_NAME}"

# Detect platform and open external terminal
OS=$(uname -s)
case "$OS" in
  MINGW*|MSYS*|CYGWIN*)
    if command -v wt.exe >/dev/null 2>&1; then
      wt.exe new-tab --title "Shelly" cmd /k "$CMD" 2>/dev/null &
    elif command -v powershell.exe >/dev/null 2>&1; then
      cmd.exe /c "start \"Shelly\" powershell -NoExit -Command \"$CMD\"" 2>/dev/null &
    else
      cmd.exe /c "start \"Shelly\" cmd /k $CMD" 2>/dev/null &
    fi
    ;;
  Darwin)
    ESCAPED=$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
    osascript -e "tell application \"Terminal\"" \
              -e "activate" \
              -e "do script \"$ESCAPED\"" \
              -e "end tell" 2>/dev/null
    ;;
  Linux)
    if command -v x-terminal-emulator >/dev/null 2>&1; then
      nohup x-terminal-emulator -e bash -c "$CMD; exec bash" >/dev/null 2>&1 &
    elif command -v gnome-terminal >/dev/null 2>&1; then
      nohup gnome-terminal -- bash -c "$CMD; exec bash" >/dev/null 2>&1 &
    elif command -v konsole >/dev/null 2>&1; then
      nohup konsole -e bash -c "$CMD; exec bash" >/dev/null 2>&1 &
    elif command -v xfce4-terminal >/dev/null 2>&1; then
      nohup xfce4-terminal -e "bash -c \"$CMD; exec bash\"" >/dev/null 2>&1 &
    elif command -v xterm >/dev/null 2>&1; then
      nohup xterm -e bash -c "$CMD; exec bash" >/dev/null 2>&1 &
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

JSON_CMD=$(printf '%s' "$CMD" | sed 's/[\\]/\\\\/g; s/"/\\"/g')
printf '{"decision":"block","reason":"Opened external terminal: %s"}\n' "$JSON_CMD"
exit 0
