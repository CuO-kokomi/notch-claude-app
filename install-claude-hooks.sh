#!/usr/bin/env zsh
set -euo pipefail

# 安装 Claude Code hook 脚本，并把 hook 配置合并进全局 settings.json。
claude_dir="$HOME/.claude"
hooks_dir="$claude_dir/hooks"
settings_file="$claude_dir/settings.json"
hook_file="$hooks_dir/notch-status.sh"
mkdir -p "$hooks_dir"

cat > "$hook_file" <<'HOOK'
#!/usr/bin/env zsh
set -euo pipefail

status_dir="$HOME/.claude-code-notch"
status_file="$status_dir/status.json"
event="${1:-idle}"
mkdir -p "$status_dir"

case "$event" in
  # 这些状态名会被 Swift app 映射为图标、颜色和说明文字。
  session_start|prompt)
    state="thinking"
    ;;
  pre_tool)
    state="running"
    ;;
  post_tool)
    state="thinking"
    ;;
  permission)
    state="allow"
    ;;
  notification)
    if jq -e '(.message // .notification // .title // "" | tostring | test("permission|allow|Permission|Allow|权限|批准|确认|是否"))' >/dev/null 2>&1; then
      state="allow"
    else
      state="waiting"
    fi
    ;;
  stop)
    state="waiting"
    ;;
  failure)
    state="error"
    ;;
  *)
    state="$event"
    ;;
esac

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"status":"%s","source":"claude-code-hook","updatedAt":"%s"}\n' "$state" "$now" > "$status_file"
HOOK

chmod +x "$hook_file"

if [[ ! -f "$settings_file" ]]; then
  printf '{}\n' > "$settings_file"
fi

tmp_file="$(mktemp)"
# 只覆盖本 app 需要的 hook 事件，保留 settings.json 里的其它配置。
jq --arg hook "$hook_file" '
  .hooks = (.hooks // {}) |
  .hooks.SessionStart = [{"hooks":[{"type":"command","command":($hook + " session_start 2>/dev/null || true"),"timeout":5}]}] |
  .hooks.UserPromptSubmit = [{"hooks":[{"type":"command","command":($hook + " prompt 2>/dev/null || true"),"timeout":5}]}] |
  .hooks.PermissionRequest = [{"matcher":"Bash|Write|Edit|Read|Agent|WebFetch|WebSearch","hooks":[{"type":"command","command":($hook + " permission 2>/dev/null || true"),"timeout":5}]}] |
  .hooks.PreToolUse = [{"matcher":"Bash|Write|Edit|Read|Agent|WebFetch|WebSearch","hooks":[{"type":"command","command":($hook + " pre_tool 2>/dev/null || true"),"timeout":5}]}] |
  .hooks.PostToolUse = [{"matcher":"Bash|Write|Edit|Read|Agent|WebFetch|WebSearch","hooks":[{"type":"command","command":($hook + " post_tool 2>/dev/null || true"),"timeout":5}]}] |
  .hooks.PostToolUseFailure = [{"matcher":"Bash|Write|Edit|Read|Agent|WebFetch|WebSearch","hooks":[{"type":"command","command":($hook + " failure 2>/dev/null || true"),"timeout":5}]}] |
  .hooks.Notification = [{"hooks":[{"type":"command","command":($hook + " notification 2>/dev/null || true"),"timeout":5}]}] |
  .hooks.Stop = [{"hooks":[{"type":"command","command":($hook + " stop 2>/dev/null || true"),"timeout":5}]}]
' "$settings_file" > "$tmp_file"
mv "$tmp_file" "$settings_file"

echo "Installed Claude Code notch hooks:"
echo "  $hook_file"
echo "Updated settings:"
echo "  $settings_file"
echo "Restart Claude Code or open /hooks once if the current session does not pick up changes."
