#!/usr/bin/env zsh
set -euo pipefail

# 依赖安装: brew install create-dmg  或  npm install -g create-dmg

mkdir -p ./NotchDMG
cp -R NotchClaudeApp.app ./NotchDMG/
cp install-claude-hooks.sh ./NotchDMG/

create-dmg \
  --volname "NotchClaude" \
  --window-pos 200 120 \
  --window-size 650 400 \
  --icon-size 100 \
  --icon "NotchClaudeApp.app" 150 190 \
  --icon "install-claude-hooks.sh" 300 190 \
  --hide-extension "NotchClaudeApp.app" \
  --app-drop-link 480 190 \
  NotchClaude.dmg \
  ./NotchDMG

rm -rf ./NotchDMG
echo "Done: NotchClaude.dmg"
