#!/bin/sh
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

sep=' \033[2;37m|\033[0m '
parts=""

# add <colored-text>: appends a separator first if parts already has content,
# so items never run together and there's never a stray leading/trailing sep.
add() {
  if [ -z "$parts" ]; then
    parts="$1"
  else
    parts=$(printf '%s%b%s' "$parts" "$sep" "$1")
  fi
}

# Model (bold cyan — the anchor item)
add "$(printf '\033[1;36m%s\033[0m' "$model")"

# Effort level (bold yellow), if present
if [ -n "$effort" ]; then
  add "$(printf '\033[1;33meffort:%s\033[0m' "$effort")"
fi

# Current workspace (bold blue), with $HOME shortened to ~
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
if [ -n "$dir" ]; then
  case "$dir" in
    "$HOME") dir='~' ;;
    "$HOME"/*) dir="~${dir#"$HOME"}" ;;
  esac
  add "$(printf '\033[1;34m%s\033[0m' "$dir")"
fi

# Context usage (green if low, yellow if medium, red if high), if present
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  if [ "$used_int" -ge 80 ]; then
    color='\033[1;31m'
  elif [ "$used_int" -ge 50 ]; then
    color='\033[1;33m'
  else
    color='\033[1;32m'
  fi
  add "$(printf '%bctx:%d%%\033[0m' "$color" "$used_int")"
fi

# Session running time (dim blue — secondary but still legible), from cost.total_duration_ms
if [ -n "$duration_ms" ]; then
  total_sec=$((duration_ms / 1000))
  h=$((total_sec / 3600))
  m=$(((total_sec % 3600) / 60))
  s=$((total_sec % 60))
  if [ "$h" -gt 0 ]; then
    time_str=$(printf '%dh%02dm' "$h" "$m")
  elif [ "$m" -gt 0 ]; then
    time_str=$(printf '%dm%02ds' "$m" "$s")
  else
    time_str=$(printf '%ds' "$s")
  fi
  add "$(printf '\033[1;94m⏱ %s\033[0m' "$time_str")"
fi

# Session cost (bold magenta), from cost.total_cost_usd
if [ -n "$cost" ]; then
  add "$(printf '\033[1;35m$%.2f\033[0m' "$cost")"
fi

# Lines changed this session, if any
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
  add "$(printf '\033[1;32m+%s\033[0m/\033[1;31m-%s\033[0m' "$lines_added" "$lines_removed")"
fi

printf '%s' "$parts"