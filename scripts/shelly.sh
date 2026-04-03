#!/usr/bin/env bash

# Read hook input from stdin
INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null) || exit 0

if [ -z "$PROMPT" ]; then
  exit 0
fi

# Case-insensitive prefix matching
LOWER=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')
CMD=""

if [ "${PROMPT#!}" != "$PROMPT" ]; then
  CMD="${PROMPT#!}"
elif [ "${LOWER#/shelly }" != "$LOWER" ]; then
  CMD="${PROMPT#????????}"
elif [ "$LOWER" = "/shelly" ]; then
  jq -n '{"decision":"block","reason":"Usage: !<command> or /shelly <command>"}'
  exit 0
else
  exit 0
fi

# Trim leading whitespace
CMD=$(printf '%s' "$CMD" | sed 's/^[[:space:]]*//')

if [ -z "$CMD" ]; then
  jq -n '{"decision":"block","reason":"Usage: !<command> or /shelly <command>"}'
  exit 0
fi

# Detect platform and open external terminal
OS=$(uname -s)
case "$OS" in
  MINGW*|MSYS*|CYGWIN*)
    cmd.exe /c "start \"Shelly\" cmd /k $CMD" 2>/dev/null &
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
      jq -n '{"decision":"block","reason":"No terminal emulator found. Install x-terminal-emulator, gnome-terminal, konsole, xfce4-terminal, or xterm."}'
      exit 0
    fi
    ;;
  *)
    jq -n --arg os "$OS" '{"decision":"block","reason":"Unsupported platform: \($os)"}'
    exit 0
    ;;
esac

jq -n --arg cmd "$CMD" '{"decision":"block","reason":"Opened external terminal: \($cmd)"}'
exit 0
