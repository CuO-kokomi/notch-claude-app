# 灵动岛 Claude

一个为 MacBook Notch 设计的 Claude Code 状态悬浮面板，收起时贴合 notch 显示简洁状态，鼠标悬停展开为信息面板。

## 效果

- **收起态**：贴合屏幕顶部 notch，显示 Claude Code 实时状态（Thinking / Running / Waiting / Needs Allow / Error）+ 计时器进度
- **展开态**：鼠标悬停展开为 720×188 圆角面板，包含 Claude 状态卡片、月历、正/倒计时器、系统 CPU/内存/网速

## 功能

| 模块 | 内容 |
|------|------|
| Claude 状态 | 未连接/Idle/Thinking/Running/Waiting/Needs Allow/Error，自动读取 Claude Code hooks 写入的本地状态 |
| 日历 | 当月月历，今天高亮 |
| 计时器 | 正计时 / 倒计时，快捷预设（1分/5分/15分），分秒独立上下调节（支持长按），收起态同步显示进度 |
| 系统信息 | 2×2 网格：CPU、内存、上传网速、下载网速，每 2 秒刷新 |

## 安装

### 方式一：DMG 安装（推荐）

从 [Releases](../../releases) 下载 `NotchClaude.dmg`，打开后将 `NotchClaudeApp.app` 拖入 `Applications`，再双击 `install-claude-hooks.sh` 完成 Claude Code hook 配置。

### 方式二：从源码构建

```sh
git clone https://github.com/chenhaha/notch-claude-app.git
cd notch-claude-app
chmod +x build.sh && ./build.sh
# 将生成的 NotchClaudeApp.app 拖入 /Applications
```

### 配置 Claude Code 状态同步

运行一次安装脚本，自动写入 hooks 到 `~/.claude/settings.json`：

```sh
./install-claude-hooks.sh
```

脚本会：
- 安装 `~/.claude/hooks/notch-status.sh`
- 在 `~/.claude/settings.json` 中添加 SessionStart / PreToolUse / PostToolUse / Notification / Stop 等 hook 事件

重启 Claude Code 或打开 `/hooks` 一次即可生效。

状态文件位于 `~/.claude-code-notch/status.json`，灵动岛每 1.5s 读取一次。30 分钟无 hook 更新自动显示"未连接"。

## 操作

- **鼠标悬停 notch 区域**：展开面板
- **鼠标移走**：0.08s 后收起
- **右键面板**：重置 Claude 状态 / 退出灵动岛

## 兼容性

- macOS 13.0+
- 带 notch 的 MacBook（非 notch 机型也能用，只是位置靠近屏幕顶部中央）

## 技术栈

- SwiftUI + AppKit
- `NSPanel` borderless / nonactivating
- Claude Code hooks → 本地 JSON → Swift 轮询
- Mach API 读取 CPU/内存
- `getifaddrs` 读网络接口字节数计算网速

## 许可

MIT
