#!/bin/bash

# 构建应用的脚本

# 设置变量
APP_NAME="BtBar"
VERSION="1.0"
BUNDLE_ID="com.example.$APP_NAME"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"

# 清理旧构建
rm -rf "$APP_DIR"
rm -rf "$BUILD_DIR"
rm -rf ".build" # 清理整个.build目录

# 构建应用
swift build -c release --build-path .build

# 创建应用包结构
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 复制可执行文件
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/"

# 复制图标文件
cp "Resources/AppIcon.png" "$APP_DIR/Contents/Resources/"

# 复制其他资源文件
cp -r "Resources/"* "$APP_DIR/Contents/Resources/"

# 创建Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>BtBar needs access to Bluetooth to manage your devices</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>BtBar needs access to Bluetooth peripherals to manage your devices</string>
    <key>NSUserNotificationUsageDescription</key>
    <string>BtBar needs to send notifications for low battery alerts</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.png</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSRequiresCarbon</key>
    <false/>
    <key>LSEnvironment</key>
    <dict/>
</dict>
</plist>
EOL

# 创建PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# 设置执行权限
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$0"

echo "应用构建完成: $APP_DIR"
echo "你可以通过以下命令运行应用:"
echo "open $APP_DIR"
echo "或者直接双击 $APP_DIR"
