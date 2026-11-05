#!/bin/bash
# Install/uninstall statusline.sh into one or more Claude Code config dirs.
#   ./install.sh                     → ~/.claude
#   ./install.sh ~/.claude-s2 ...    → given dirs
#   ./install.sh --all               → ~/.claude and every ~/.claude-* dir with settings.json
#   ./install.sh --list              → show current statusLine per dir
#   ./install.sh --uninstall [dirs|--all]  → restore previous statusLine from backup
#   --dry-run                        → print what would change
set -euo pipefail
command -v jq >/dev/null || { echo "jq required (brew install jq)"; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/statusline.sh"
CMD="bash \"$SCRIPT\""
mode=install dry=0 dirs=()

for a in "$@"; do
  case "$a" in
    --all) for d in "$HOME/.claude" "$HOME"/.claude-*; do [ -f "$d/settings.json" ] && dirs+=("$d"); done ;;
    --uninstall) mode=uninstall ;;
    --list) mode=list ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) dirs+=("${a%/}") ;;
  esac
done
[ ${#dirs[@]} -eq 0 ] && { if [ "$mode" = list ]; then for d in "$HOME/.claude" "$HOME"/.claude-*; do [ -f "$d/settings.json" ] && dirs+=("$d"); done; else dirs=("$HOME/.claude"); fi; }

for d in "${dirs[@]}"; do
  f="$d/settings.json"
  if [ "$mode" = list ]; then
    printf '%-32s %s\n' "$d" "$(jq -c '.statusLine.command // "none"' "$f" 2>/dev/null)"; continue
  fi
  [ -d "$d" ] || { echo "skip $d (no dir)"; continue; }
  [ -f "$f" ] || echo '{}' > "$f"
  jq empty "$f" 2>/dev/null || { echo "skip $f (invalid JSON)"; continue; }

  if [ "$mode" = install ]; then
    cur=$(jq -c '.statusLine // null' "$f")
    if [ "$(jq -r '.statusLine.command // ""' "$f")" = "$CMD" ]; then echo "ok   $d (already installed)"; continue; fi
    echo "set  $d  (was: $cur)"
    [ $dry -eq 1 ] && continue
    printf '%s\n' "$cur" > "$d/.statusline-prev.json"
    cp "$f" "$f.bak-statusline-$(date +%Y%m%d-%H%M%S)"
    tmp=$(mktemp); jq --arg c "$CMD" '.statusLine = {type:"command", command:$c, padding:0}' "$f" > "$tmp" && mv "$tmp" "$f"
  else
    prev=null; [ -f "$d/.statusline-prev.json" ] && prev=$(cat "$d/.statusline-prev.json")
    echo "undo $d  (restore: $prev)"
    [ $dry -eq 1 ] && continue
    cp "$f" "$f.bak-statusline-$(date +%Y%m%d-%H%M%S)"
    tmp=$(mktemp)
    if [ "$prev" = null ]; then jq 'del(.statusLine)' "$f" > "$tmp"; else jq --argjson p "$prev" '.statusLine = $p' "$f" > "$tmp"; fi
    mv "$tmp" "$f"; rm -f "$d/.statusline-prev.json"
  fi
done
