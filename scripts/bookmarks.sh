#!/usr/bin/env bash

# Bookmark CRUD for claude-loves-shelly
# Usage: bookmarks.sh <operation> <plugin_root> [name] [command...]

OPERATION="$1"
PLUGIN_ROOT="$2"
NAME="$3"
shift 3 2>/dev/null
COMMAND="$*"
BOOKMARKS_FILE="$PLUGIN_ROOT/bookmarks.json"

# Ensure bookmarks file exists
if [ ! -f "$BOOKMARKS_FILE" ]; then
  printf '{}' > "$BOOKMARKS_FILE"
fi

case "$OPERATION" in
  add)
    if [ -z "$NAME" ]; then
      printf 'Usage: >+<name> <command>\n'
      exit 1
    fi
    if [ -z "$COMMAND" ]; then
      # Lookup mode: no command provided, show existing bookmark
      EXISTING=$(node -e "
        const d=JSON.parse(require('fs').readFileSync('$BOOKMARKS_FILE','utf8'));
        if(d['$NAME']) console.log('$NAME: '+d['$NAME']);
        else { console.log(\"Bookmark '$NAME' does not exist\"); process.exit(1); }
      " 2>/dev/null)
      printf '%s\n' "$EXISTING"
      exit 0
    fi
    # Save bookmark
    node -e "
      const fs=require('fs');
      const d=JSON.parse(fs.readFileSync('$BOOKMARKS_FILE','utf8'));
      d['$NAME']=$(printf '%s' "$COMMAND" | node -e "process.stdout.write(JSON.stringify(require('fs').readFileSync(0,'utf8')))");
      fs.writeFileSync('$BOOKMARKS_FILE',JSON.stringify(d,null,2)+'\n');
    " 2>/dev/null
    printf "Saved bookmark '%s': %s\n" "$NAME" "$COMMAND"
    ;;
esac
