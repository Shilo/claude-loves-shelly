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
      EXISTING=$(BOOKMARKS_FILE="$BOOKMARKS_FILE" BM_NAME="$NAME" node -e "
        const d=JSON.parse(require('fs').readFileSync(process.env.BOOKMARKS_FILE,'utf8'));
        const name=process.env.BM_NAME;
        if(d[name]) console.log(name+': '+d[name]);
        else { console.log(\"Bookmark '\"+name+\"' does not exist\"); process.exit(1); }
      " 2>/dev/null)
      STATUS=$?
      printf '%s\n' "$EXISTING"
      exit $STATUS
    fi
    # Save bookmark
    BOOKMARKS_FILE="$BOOKMARKS_FILE" BM_NAME="$NAME" node -e "
      const fs=require('fs');
      const file=process.env.BOOKMARKS_FILE;
      const name=process.env.BM_NAME;
      const d=JSON.parse(fs.readFileSync(file,'utf8'));
      d[name]=$(printf '%s' "$COMMAND" | node -e "process.stdout.write(JSON.stringify(require('fs').readFileSync(0,'utf8')))");
      fs.writeFileSync(file,JSON.stringify(d,null,2)+'\n');
    " 2>/dev/null
    printf "Saved bookmark '%s': %s\n" "$NAME" "$COMMAND"
    ;;

  remove)
    if [ -z "$NAME" ]; then
      printf 'Usage: >-<name>\n'
      exit 1
    fi
    RESULT=$(BOOKMARKS_FILE="$BOOKMARKS_FILE" BM_NAME="$NAME" node -e "
      const fs=require('fs');
      const file=process.env.BOOKMARKS_FILE;
      const name=process.env.BM_NAME;
      const d=JSON.parse(fs.readFileSync(file,'utf8'));
      if(!d[name]){ console.log(\"Bookmark '\"+name+\"' does not exist\"); process.exit(1); }
      delete d[name];
      fs.writeFileSync(file,JSON.stringify(d,null,2)+'\n');
      console.log(\"Removed bookmark '\"+name+\"'\");
    " 2>/dev/null)
    STATUS=$?
    printf '%s\n' "$RESULT"
    exit $STATUS
    ;;

  list)
    RESULT=$(BOOKMARKS_FILE="$BOOKMARKS_FILE" node -e "
      const d=JSON.parse(require('fs').readFileSync(process.env.BOOKMARKS_FILE,'utf8'));
      const keys=Object.keys(d);
      if(!keys.length){ console.log('No bookmarks saved'); process.exit(0); }
      keys.forEach(k=>console.log(k+': '+d[k]));
    " 2>/dev/null)
    printf '%s\n' "$RESULT"
    ;;

  resolve)
    # Look up bookmark by name and substitute positional args
    # Outputs resolved command to stdout, exits 1 if not found
    ARGS="$COMMAND"
    RESULT=$(BOOKMARKS_FILE="$BOOKMARKS_FILE" BM_NAME="$NAME" BM_ARGS="$ARGS" node -e "
      const d=JSON.parse(require('fs').readFileSync(process.env.BOOKMARKS_FILE,'utf8'));
      const name=process.env.BM_NAME;
      if(!d[name]){ process.exit(1); }
      let cmd=d[name];
      const args=(process.env.BM_ARGS||'').split(/\s+/).filter(Boolean);
      args.forEach((a,i)=>{ cmd=cmd.split('{'+(i+1)+'}').join(a); });
      process.stdout.write(cmd);
    " 2>/dev/null)
    if [ $? -eq 0 ]; then
      printf '%s' "$RESULT"
    else
      exit 1
    fi
    ;;
esac
