#!/bin/bash
# Claude Code status line: model │ ctx % used/size │ 5h % ↻reset │ wk % ↻reset │ user
# Data: status line stdin JSON only (no network, no MCP). Email from <config>/.claude.json.
# One jq call parses stdin + account file and formats everything (dates, token counts).
# Capture one stdin sample: touch "$(dirname "$0")/samples/.capture"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
in=$(cat)

if [ -f "$HERE/samples/.capture" ] && [ ! -L "$HERE/samples/.capture" ]; then
  printf '%s\n' "$in" > "$HERE/samples/stdin-$(date +%Y%m%d-%H%M%S).json"
  rm -f "$HERE/samples/.capture"
fi

# Email: CLAUDE_CONFIG_DIR/.claude.json when set, else ~/.claude.json
if [ -n "$CLAUDE_CONFIG_DIR" ]; then acct="$CLAUDE_CONFIG_DIR/.claude.json"; else acct="$HOME/.claude.json"; fi
files=(); [ -r "$acct" ] && files+=("$acct")

# Fields, separated by \x1f (non-whitespace IFS keeps empty fields):
#   model, ctx %, ctx tokens "used/size", 5h %, 5h reset, wk %, wk reset, user
IFS=$'\x1f' read -r model ctx ctxtok h5 h5r wk wkr user < <(
  printf '%s' "$in" | jq -rs '
    def clean: tostring | gsub("[\u0000-\u001f\u007f]"; "")
            | gsub("\\\\"; "\\\\");   # double backslashes: output goes through printf %b
    def human: if . >= 1e6 then "\(. / 1e5 | floor / 10)M" | sub("\\.0M$"; "M")
               elif . >= 1e3 then "\(. / 1e2 | floor / 10)k" else "\(floor)" end;
    def epoch: if type == "number" then . elif type == "string" and test("^[0-9]+(\\.[0-9]+)?$") then tonumber
               elif type == "string" then (sub("\\.[0-9]+"; "") | sub("(\\+00:?00)?$"; "") | sub("Z?$"; "Z")
                                          | try fromdateiso8601 catch null)
               else null end | if . != null and . > 9999999999 then . / 1000 else . end;
    def reset: epoch | if . == null then "" else floor as $t
               | ($t | strflocaltime("%-I:%M%p") | ascii_downcase) as $w
               | if ($t | strflocaltime("%F")) == (now | strflocaltime("%F")) then $w
                 else ($t | strflocaltime("%a ")) + $w end end;
    def num: if . == null then "" else tostring end;
    (.[0] // {}) as $s | (.[1] // {}) as $a
    | ($s.context_window // {}) as $c
    | ($c.current_usage // null) as $u
    | (if $u then ($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0)
                 + ($u.cache_read_input_tokens // 0)
       else null end) as $used
    | ($c.context_window_size // 0) as $size
    | [ ($s.model.display_name // "" | clean),
        ($c.used_percentage // (if $used and $size > 0 then $used * 100 / $size else null end) | num),
        (if $used and $used > 0 then ($used | human) + (if $size > 0 then "/" + ($size | human) else "" end) else "" end),
        ($s.rate_limits.five_hour.used_percentage | num),
        ($s.rate_limits.five_hour.resets_at | reset),
        ($s.rate_limits.seven_day.used_percentage | num),
        ($s.rate_limits.seven_day.resets_at | reset),
        ($a.oauthAccount.emailAddress // "" | clean | sub("@.*$"; ""))
      ] | map(gsub("\u001f"; "")) | join("\u001f")
  ' - "${files[@]}" 2>/dev/null
)

color() { # $1 = pct number → ANSI color code
  local p=${1%.*}; [ -z "$p" ] && { printf '90'; return; }
  if [ "$p" -ge 80 ]; then printf '31'; elif [ "$p" -ge 50 ]; then printf '33'; else printf '32'; fi
}
pct() { # colored "NN%" or dim "--"
  if [ -n "$1" ]; then printf '\033[%sm%.0f%%\033[0m' "$(color "$1")" "$1"; else printf '\033[90m--\033[0m'; fi
}
rst() { [ -n "$1" ] && printf ' \033[94m↻%s\033[0m' "$1"; }

# Optional caveman badge: only when the plugin is installed and its mode flag exists
badge=""
if [ -f "$CFG/.caveman-active" ]; then
  cave=""
  for f in "$CFG"/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh; do
    [ -f "$f" ] && { [ -z "$cave" ] || [ "$f" -nt "$cave" ]; } && cave=$f
  done
  [ -n "$cave" ] && badge=$(bash "$cave" </dev/null 2>/dev/null)
fi

sep=' \033[90m│\033[0m '
out=""
[ -n "$badge" ] && out+="$badge "
out+="\033[1m${model:-?}\033[0m"
out+="${sep}ctx $(pct "$ctx")"
[ -n "$ctxtok" ] && out+=" \033[37m$ctxtok\033[0m"
out+="${sep}5h $(pct "$h5")$(rst "$h5r")"
out+="${sep}wk $(pct "$wk")$(rst "$wkr")"
[ -n "$user" ] && out+="${sep}\033[36m$user\033[0m"
printf '%b' "$out"
