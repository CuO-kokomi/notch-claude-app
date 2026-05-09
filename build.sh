#!/usr/bin/env zsh
set -euo pipefail

# ——— 构建可执行文件 ———
swift build -c release

# ——— 图标 ———
# 优先用 ico.png，否则尝试 $ICON_SRC
ICON_SRC="myico.png"
[[ -f "$ICON_SRC" ]] || ICON_SRC="$ICON_SRC"
if [[ -f "$ICON_SRC" ]]; then
    rm -rf icon.iconset
    mkdir -p icon.iconset
    sips -z 16 16   "$ICON_SRC" --out icon.iconset/icon_16x16.png
    sips -z 32 32   $ICON_SRC --out icon.iconset/icon_16x16@2x.png
    sips -z 32 32   $ICON_SRC --out icon.iconset/icon_32x32.png
    sips -z 64 64   $ICON_SRC --out icon.iconset/icon_32x32@2x.png
    sips -z 128 128 $ICON_SRC --out icon.iconset/icon_128x128.png
    sips -z 256 256 $ICON_SRC --out icon.iconset/icon_128x128@2x.png
    sips -z 256 256 $ICON_SRC --out icon.iconset/icon_256x256.png
    sips -z 512 512 $ICON_SRC --out icon.iconset/icon_256x256@2x.png
    sips -z 512 512 $ICON_SRC --out icon.iconset/icon_512x512.png
    sips -z 1024 1024 $ICON_SRC --out icon.iconset/icon_512x512@2x.png
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

# ——— 写入 Info.plist ———
cat > NotchClaudeApp.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NotchClaudeApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.notchclaude.app</string>
    <key>CFBundleName</key>
    <string>灵动岛 Claude</string>
    <key>CFBundleDisplayName</key>
    <string>灵动岛 Claude</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>灵动岛需要控制音乐播放器以显示当前播放信息</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# ——— 签名 ———
chmod +x NotchClaudeApp.app/Contents/MacOS/NotchClaudeApp
codesign --force --deep --sign - NotchClaudeApp.app

echo "Done: NotchClaudeApp.app"
