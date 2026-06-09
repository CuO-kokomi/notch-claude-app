#!/usr/bin/env zsh
set -euo pipefail

# 安装 Claude Code hook 脚本，并把 hook 配置合并进全局 settings.json。
claude_dir="$HOME/.claude"
hooks_dir="$claude_dir/hooks"
settings_file="$claude_dir/settings.json"
hook_file="$hooks_dir/notch-status.sh"
mkdir -p "$hooks_dir"

# 升级检测：安装前读旧 hook 的版本标记，安装后对比报告。
# 注意：HOOK_VERSION 必须与下方 heredoc 内 "notch-hook-version" 标记保持一致。
HOOK_VERSION=4
prev_version=""
if [[ -f "$hook_file" ]]; then
  prev_version="$(grep -m1 'notch-hook-version:' "$hook_file" 2>/dev/null | sed -E 's/.*notch-hook-version:[[:space:]]*([0-9]+).*/\1/' || true)"
fi

cat > "$hook_file" <<'HOOK'
#!/usr/bin/env zsh
# notch-hook-version: 4
set -euo pipefail

status_dir="$HOME/.claude-code-notch"
status_file="$status_dir/status.json"
event="${1:-idle}"
mkdir -p "$status_dir"

# stdin 只能读一次，先整体抓进变量，后续从中提取工具上下文。
input="$(cat 2>/dev/null || true)"

# 从 hook JSON 取一个字段，失败/无 jq 时返回空串。
json_get() {
  printf '%s' "$input" | jq -r "$1" 2>/dev/null || true
}

tool=""
detail=""
started=""

case "$event" in
  # 这些状态名会被 Swift app 映射为图标、颜色和说明文字。
  session_start|prompt)
    state="thinking"
    ;;
  pre_tool)
    state="running"
    tool="$(json_get '.tool_name // empty')"
    case "$tool" in
      Bash)
        detail="$(json_get '.tool_input.command // empty')"
        ;;
      Edit|MultiEdit|Write|Read)
        fp="$(json_get '.tool_input.file_path // empty')"
        detail="${fp:t}"
        ;;
      NotebookEdit)
        fp="$(json_get '.tool_input.notebook_path // empty')"
        detail="${fp:t}"
        ;;
      Task|Agent)
        detail="$(json_get '.tool_input.subagent_type // .tool_input.description // empty')"
        ;;
      WebFetch|WebSearch)
        detail="$(json_get '.tool_input.url // .tool_input.query // empty')"
        ;;
    esac
    # 工具开始时间，供 app 计算耗时。
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ;;
  post_tool)
    state="thinking"
    ;;
  permission)
    state="allow"
    tool="$(json_get '.tool_name // empty')"
    ;;
  notification)
    msg="$(json_get '(.message // .notification // .title // "") | tostring')"
    if printf '%s' "$msg" | grep -Eiq 'permission|allow|权限|批准|确认|是否'; then
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
    tool="$(json_get '.tool_name // empty')"
    detail="$(json_get '(.tool_response.error // .tool_response // .error // "") | tostring')"
    ;;
  *)
    state="$event"
    ;;
esac

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# 用 jq 构造输出：在 jq 里按 codepoint 截断 detail（避免 head -c 切坏 UTF-8），
# 空字段不写出，保持向后兼容。
jq -n \
  --arg status "$state" \
  --arg tool "$tool" \
  --arg detail "$detail" \
  --arg started "$started" \
  --arg now "$now" \
  '{status: $status, source: "claude-code-hook", updatedAt: $now}
   + (if $tool    != "" then {tool: $tool} else {} end)
   + (if $detail  != "" then {detail: ($detail | gsub("\\s+"; " ") | .[0:56])} else {} end)
   + (if $started != "" then {toolStartedAt: $started} else {} end)' \
  > "$status_file"
HOOK

chmod +x "$hook_file"

if [[ ! -f "$settings_file" ]]; then
  printf '{}\n' > "$settings_file"
fi

tmp_file="$(mktemp)"
# 追加合并：保留 settings.json 里已有的其它 hook（如 Clawd on Desk），
# 只在对应事件数组后面追加 notch 的 hook；重复运行时先剔除旧的 notch 条目以防叠加。
jq --arg hook "$hook_file" '
  # 把一个 hook 分组追加到指定事件：先滤掉所有“命令里含本脚本路径”的旧 notch 条目，再追加新的。
  def add_notch($event; $entry):
    .hooks[$event] = (
      ((.hooks[$event] // [])
        | map(select(any(.hooks[]?; (.command // "") | contains($hook)) | not)))
      + [$entry]
    );

  .hooks = (.hooks // {})
  | add_notch("SessionStart";
      {"hooks":[{"type":"command","command":($hook + " session_start 2>/dev/null || true"),"timeout":5}]})
  | add_notch("UserPromptSubmit";
      {"hooks":[{"type":"command","command":($hook + " prompt 2>/dev/null || true"),"timeout":5}]})
  | add_notch("PermissionRequest";
      {"matcher":"Bash|Write|Edit|Read|Agent|WebFetch|WebSearch","hooks":[{"type":"command","command":($hook + " permission 2>/dev/null || true"),"timeout":5}]})
  | add_notch("PreToolUse";
      {"matcher":"Bash|Write|Edit|Read|Agent|WebFetch|WebSearch","hooks":[{"type":"command","command":($hook + " pre_tool 2>/dev/null || true"),"timeout":5}]})
  | add_notch("PostToolUse";
      {"matcher":"Bash|Write|Edit|Read|Agent|WebFetch|WebSearch","hooks":[{"type":"command","command":($hook + " post_tool 2>/dev/null || true"),"timeout":5}]})
  | add_notch("PostToolUseFailure";
      {"matcher":"Bash|Write|Edit|Read|Agent|WebFetch|WebSearch","hooks":[{"type":"command","command":($hook + " failure 2>/dev/null || true"),"timeout":5}]})
  | add_notch("Notification";
      {"hooks":[{"type":"command","command":($hook + " notification 2>/dev/null || true"),"timeout":5}]})
  | add_notch("Stop";
      {"hooks":[{"type":"command","command":($hook + " stop 2>/dev/null || true"),"timeout":5}]})
' "$settings_file" > "$tmp_file"
mv "$tmp_file" "$settings_file"

# 报告这次是全新安装、升级还是同版本刷新。
if [[ -z "$prev_version" ]]; then
  echo "Installed notch hook (v$HOOK_VERSION)."
elif [[ "$prev_version" != "$HOOK_VERSION" ]]; then
  echo "Upgraded notch hook v$prev_version -> v$HOOK_VERSION."
else
  echo "Refreshed notch hook (already v$HOOK_VERSION)."
fi
echo "Merged into settings (existing hooks from other tools preserved):"
echo "  $hook_file"
echo "  $settings_file"
echo "Restart Claude Code or open /hooks once if the current session does not pick up changes."
