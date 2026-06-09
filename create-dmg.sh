#!/usr/bin/env zsh
set -euo pipefail

# 依赖安装: brew install create-dmg  或  npm install -g create-dmg

mkdir -p ./NotchDMG
cp -R NotchClaudeApp.app ./NotchDMG/
# hook 已由 app 启动时自动安装/升级，无需在 DMG 里附带安装脚本。

create-dmg \
  --volname "NotchClaude" \
  --window-pos 200 120 \
  --window-size 540 380 \
  --icon-size 100 \
  --icon "NotchClaudeApp.app" 140 180 \
  --hide-extension "NotchClaudeApp.app" \
  --app-drop-link 400 180 \
  NotchClaude.dmg \
  ./NotchDMG

rm -rf ./NotchDMG
echo "Done: NotchClaude.dmg"
