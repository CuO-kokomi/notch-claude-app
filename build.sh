#!/usr/bin/env zsh
set -euo pipefail

# ——— 构建可执行文件 ———
swift build -c release

# ——— 图标（如果有 myico.png） ———
if [[ -f myico.png ]]; then
    rm -rf icon.iconset
    mkdir -p icon.iconset
    sips -z 16 16   myico.png --out icon.iconset/icon_16x16.png
    sips -z 32 32   myico.png --out icon.iconset/icon_16x16@2x.png
    sips -z 32 32   myico.png --out icon.iconset/icon_32x32.png
    sips -z 64 64   myico.png --out icon.iconset/icon_32x32@2x.png
    sips -z 128 128 myico.png --out icon.iconset/icon_128x128.png
    sips -z 256 256 myico.png --out icon.iconset/icon_128x128@2x.png
    sips -z 256 256 myico.png --out icon.iconset/icon_256x256.png
    sips -z 512 512 myico.png --out icon.iconset/icon_256x256@2x.png
    sips -z 512 512 myico.png --out icon.iconset/icon_512x512.png
    sips -z 1024 1024 myico.png --out icon.iconset/icon_512x512@2x.png
    iconutil -c icns icon.iconset -o AppIcon.icns
    rm -rf icon.iconset
fi

# ——— 组装 .app ———
rm -rf NotchClaudeApp.app
mkdir -p NotchClaudeApp.app/Contents/MacOS NotchClaudeApp.app/Contents/Resources
cp .build/release/NotchClaudeApp NotchClaudeApp.app/Contents/MacOS/

if [[ -f AppIcon.icns ]]; then
    cp AppIcon.icns NotchClaudeApp.app/Contents/Resources/
fi

# ——— 签名 ———
chmod +x NotchClaudeApp.app/Contents/MacOS/NotchClaudeApp
codesign --force --deep --sign - NotchClaudeApp.app

echo "Done: NotchClaudeApp.app"
