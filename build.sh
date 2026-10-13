#!/bin/bash
set -euo pipefail

# 构建并打包 macTabs 为可双击运行的 .app
cd "$(dirname "$0")"

APP_NAME="macTabs"
BUNDLE="${APP_NAME}.app"
BIN_NAME="macTabs"

echo ">>> 编译 release..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${BIN_NAME}"

echo ">>> 组装 ${BUNDLE} ..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${BUNDLE}/Contents/MacOS/${BIN_NAME}"

# 应用图标(放仓库 Resources/AppIcon.icns,随打包拷入)
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"
fi

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${BIN_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.mactabs</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>需要控制其它应用窗口以实现页签切换。</string>
</dict>
</plist>
PLIST

# 用本地自签名证书签名(稳定身份,TCC 授权重建后永久保持)
# 若证书不存在则回退 ad-hoc(授权会在重建后失效,需重新授权)
echo ">>> 代码签名..."
if security find-certificate -c "macTabs-SelfSign" >/dev/null 2>&1; then
    codesign --force --sign "macTabs-SelfSign" --identifier local.mactabs "${BUNDLE}"
    echo "    已用 macTabs-SelfSign 证书签名"
else
    codesign --force --sign - --identifier local.mactabs "${BUNDLE}" 2>/dev/null || true
    echo "    [警告] 未找到 macTabs-SelfSign 证书,回退 ad-hoc 签名(授权可能需重授)"
fi

echo ">>> 完成: $(pwd)/${BUNDLE}"
