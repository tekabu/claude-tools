#!/bin/bash
# Claude Code status line: model │ ctx % │ 5h % ↻countdown │ wk % ↻countdown │ user
# Data: status line stdin JSON only (no network, no MCP). Email from <config>/.claude.json.
# Capture one stdin sample: touch "$(dirname "$0")/samples/.capture"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
in=$(cat)

if [ -f "$HERE/samples/.capture" ] && [ ! -L "$HERE/samples/.capture" ]; then
  printf '%s\n' "$in" > "$HERE/samples/stdin-$(date +%Y%m%d-%H%M%S).json"
  rm -f "$HERE/samples/.capture"
fi

j() { jq -r "$1 // empty" <<<"$in" 2>/dev/null; }

model=$(j '.model.display_name')
ctx=$(j '.context_window.used_percentage')
if [ -z "$ctx" ]; then
  ctx=$(jq -r '(.context_window // {}) as $c
    | if ($c.context_window_size // 0) > 0 and $c.current_usage then
        (($c.current_usage.input_tokens // 0) + ($c.current_usage.cache_creation_input_tokens // 0)
         + ($c.current_usage.cache_read_input_tokens // 0)) * 100 / $c.context_window_size
      else empty end' <<<"$in" 2>/dev/null)
fi
tok=$(j '((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)) | select(. > 0)')
h5=$(j '.rate_limits.five_hour.used_percentage')
h5r=$(j '.rate_limits.five_hour.resets_at')
wk=$(j '.rate_limits.seven_day.used_percentage')
wkr=$(j '.rate_limits.seven_day.resets_at')

# Email: CLAUDE_CONFIG_DIR/.claude.json when set, else ~/.claude.json
if [ -n "$CLAUDE_CONFIG_DIR" ]; then acct="$CLAUDE_CONFIG_DIR/.claude.json"; else acct="$HOME/.claude.json"; fi
email=$(jq -r '.oauthAccount.emailAddress // empty' "$acct" 2>/dev/null)
user=${email%@*}

# Strip control chars from anything printed (escape-injection guard)
clean() { printf '%s' "$1" | tr -d '\000-\037\177'; }

color() { # $1 = pct number → ANSI color code
  local p=${1%.*}; [ -z "$p" ] && { printf '90'; return; }
  if [ "$p" -ge 80 ]; then printf '31'; elif [ "$p" -ge 50 ]; then printf '33'; else printf '32'; fi
}
pct() { # colored "NN%" or dim "--"
  if [ -n "$1" ]; then printf '\033[%sm%.0f%%\033[0m' "$(color "$1")" "$1"; else printf '\033[90m--\033[0m'; fi
}
until_reset() { # resets_at (epoch secs or ISO-8601) → " ↻8:20pm" (today) or " ↻Tue 11:00am"
  local r=$1 t when
  [ -z "$r" ] && return
  if [[ "$r" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then t=${r%.*}
  else t=$(TZ=UTC date -j -f %Y-%m-%dT%H:%M:%S "${r%%[.Z+]*}" +%s 2>/dev/null) || return; fi
  [ "$t" -gt 9999999999 ] && t=$((t / 1000))   # ms epoch
  when=$(date -r "$t" +%-I:%M%p | tr 'APM' 'apm')
  [ "$(date -r "$t" +%F)" != "$(date +%F)" ] && when="$(date -r "$t" +%a) $when"
  printf ' \033[94m↻%s\033[0m' "$when"
}

human() { # 65402 → 65.4k, 1234567 → 1.2M
  awk -v n="$1" 'BEGIN{ if(n>=1e6) printf "%.1fM", n/1e6; else if(n>=1e3) printf "%.1fk", n/1e3; else printf "%d", n }'
}

# Optional caveman badge (if plugin installed in this config dir)
badge=""
cave=$(ls -t "$CFG"/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh 2>/dev/null | head -1)
[ -n "$cave" ] && badge=$(bash "$cave" </dev/null 2>/dev/null)

sep=' \033[90m│\033[0m '
out=""
[ -n "$badge" ] && out+="$badge "
out+="\033[1m$(clean "${model:-?}")\033[0m"
out+="${sep}ctx $(pct "$ctx")"
[ -n "$tok" ] && out+=" \033[37m$(human "$tok")\033[0m"
out+="${sep}5h $(pct "$h5")$(until_reset "$h5r")"
out+="${sep}wk $(pct "$wk")$(until_reset "$wkr")"
[ -n "$user" ] && out+="${sep}\033[36m$(clean "$user")\033[0m"
printf '%b' "$out"
