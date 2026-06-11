#!/usr/bin/env zsh
set -euo pipefail

# 安装 Claude Code hook 脚本，并把 hook 配置合并进全局 settings.json。
claude_dir="$HOME/.claude"
hooks_dir="$claude_dir/hooks"
settings_file="$claude_dir/settings.json"
hook_file="$hooks_dir/notch-status.sh"
mkdir -p "$hooks_dir"

# 权限审批 HTTP hook 的本地端点；必须与 app 内 PermissionServer 的端口一致。
PERMISSION_URL="http://127.0.0.1:23889/permission"

# 升级检测：安装前读旧 hook 的版本标记，安装后对比报告。
# 注意：HOOK_VERSION 必须与下方 heredoc 内 "notch-hook-version" 标记保持一致。
HOOK_VERSION=5
prev_version=""
if [[ -f "$hook_file" ]]; then
  prev_version="$(grep -m1 'notch-hook-version:' "$hook_file" 2>/dev/null | sed -E 's/.*notch-hook-version:[[:space:]]*([0-9]+).*/\1/' || true)"
fi

cat > "$hook_file" <<'HOOK'
#!/usr/bin/env zsh
# notch-hook-version: 5
set -euo pipefail

base_dir="$HOME/.claude-code-notch"
sessions_dir="$base_dir/sessions"
event="${1:-idle}"
mkdir -p "$sessions_dir"

# stdin 只能读一次，先整体抓进变量，后续从中提取工具上下文。
input="$(cat 2>/dev/null || true)"

# 从 hook JSON 取一个字段，失败/无 jq 时返回空串。
json_get() {
  printf '%s' "$input" | jq -r "$1" 2>/dev/null || true
}

# 每会话一个状态文件，避免多个 Claude Code 终端互相覆盖。
session_id="$(json_get '.session_id // empty')"
[[ -z "$session_id" ]] && session_id="default"
session_id="${session_id//[^a-zA-Z0-9._-]/_}"
session_file="$sessions_dir/$session_id.json"

# 会话结束（含 /clear）：直接清掉该会话的状态文件。
if [[ "$event" == "session_end" ]]; then
  rm -f "$session_file"
  exit 0
fi

# 向上找 claude 进程 PID，供 app 做存活检测（hook 可能隔着一层 sh 包装）。
# 找不到就留空，app 退回按文件时间判过期。
claude_pid=""
walk_pid="$PPID"
for _ in 1 2 3 4 5; do
  cmd="$(ps -o comm= -p "$walk_pid" 2>/dev/null | tr -d ' ' || true)"
  if [[ "$cmd" == *claude* || "$cmd" == *node* || "$cmd" == *bun* ]]; then
    claude_pid="$walk_pid"
    break
  fi
  next="$(ps -o ppid= -p "$walk_pid" 2>/dev/null | tr -d ' ' || true)"
  [[ -z "$next" || "$next" == "0" || "$next" == "1" ]] && break
  walk_pid="$next"
done

tool=""
detail=""
started=""
result=""

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
    # 兼容：升级前已启动的会话仍按旧配置调 command hook，至少把状态标成需授权。
    state="allow"
    tool="$(json_get '.tool_name // empty')"
    ;;
  notification)
    # 兜底：旧版 Claude Code 不支持 HTTP 权限 hook 时仍能提示"需要授权"。
    msg="$(json_get '(.message // .notification // .title // "") | tostring')"
    if printf '%s' "$msg" | grep -Eiq 'permission|allow|权限|批准|确认|是否'; then
      state="allow"
    else
      state="waiting"
    fi
    ;;
  stop)
    # 完成门控：stop-hook 续跑 / 后台任务 / 会话内定时任务都说明任务还没真正交回，
    # 此时显示继续忙而不是"等待你"，避免误报完成。
    gated="$(json_get 'if (.stop_hook_active == true)
        or ((.background_tasks // []) | length > 0)
        or ((.session_crons // []) | length > 0)
      then "1" else empty end')"
    if [[ -n "$gated" ]]; then
      state="thinking"
    else
      state="waiting"
      # Claude Code 直接给最后一条回复，比解析 transcript 可靠；截 400 字符够摘要用。
      result="$(json_get '(.last_assistant_message // "") | tostring | .[0:400]')"
    fi
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

cwd="$(json_get '.cwd // empty')"
transcript_path="$(json_get '.transcript_path // empty')"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# 用 jq 构造输出：在 jq 里按 codepoint 截断 detail（避免 head -c 切坏 UTF-8），
# 空字段不写出，保持向后兼容。
jq -n \
  --arg status "$state" \
  --arg tool "$tool" \
  --arg detail "$detail" \
  --arg started "$started" \
  --arg now "$now" \
  --arg sid "$session_id" \
  --arg cwd "$cwd" \
  --arg pid "$claude_pid" \
  --arg transcript "$transcript_path" \
  --arg result "$result" \
  '{status: $status, sessionId: $sid, source: "claude-code-hook", updatedAt: $now}
   + (if $tool       != "" then {tool: $tool} else {} end)
   + (if $detail     != "" then {detail: ($detail | gsub("\\s+"; " ") | .[0:56])} else {} end)
   + (if $started    != "" then {toolStartedAt: $started} else {} end)
   + (if $cwd        != "" then {cwd: $cwd} else {} end)
   + (if $pid        != "" then {pid: ($pid | tonumber)} else {} end)
   + (if $transcript != "" then {transcriptPath: $transcript} else {} end)
   + (if $result     != "" then {result: $result} else {} end)' \
  > "$session_file"
HOOK

chmod +x "$hook_file"

if [[ ! -f "$settings_file" ]]; then
  printf '{}\n' > "$settings_file"
fi

tmp_file="$(mktemp)"
# 追加合并：保留 settings.json 里已有的其它 hook（如 Clawd on Desk），
# 只在对应事件数组后面追加 notch 的 hook；重复运行时先剔除旧的 notch 条目以防叠加。
# notch 条目识别：command 含本脚本路径，或 http url 指向本 app 的权限端口。
jq --arg hook "$hook_file" --arg permurl "$PERMISSION_URL" '
  def is_notch:
    any(.hooks[]?;
      ((.command // "") | contains("hooks/notch-status.sh"))
      or ((.url // "") | contains("127.0.0.1:23889")));

  def add_notch($event; $entry):
    .hooks[$event] = (
      ((.hooks[$event] // []) | map(select(is_notch | not)))
      + [$entry]
    );

  .hooks = (.hooks // {})
  | add_notch("SessionStart";
      {"hooks":[{"type":"command","command":($hook + " session_start 2>/dev/null || true"),"timeout":5}]})
  | add_notch("SessionEnd";
      {"hooks":[{"type":"command","command":($hook + " session_end 2>/dev/null || true"),"timeout":5}]})
  | add_notch("UserPromptSubmit";
      {"hooks":[{"type":"command","command":($hook + " prompt 2>/dev/null || true"),"timeout":5}]})
  | add_notch("PermissionRequest";
      {"matcher":"","hooks":[{"type":"http","url":$permurl,"timeout":600}]})
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

# v5 起改为每会话文件，清理 v4 的单一状态文件。
rm -f "$HOME/.claude-code-notch/status.json"

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
