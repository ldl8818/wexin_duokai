#!/bin/bash
# 生成自包含的桌面启动器：检查主微信版本，安全同步已退出的分身后启动。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_APP="$HOME/Desktop/微信三开.app"
PYTHON_BIN=$(command -v python3)
mkdir -p "$SCRIPT_DIR/.tmp"
BUILD_DIR=$(mktemp -d "$SCRIPT_DIR/.tmp/launcher-build.XXXXXX")
APP="$BUILD_DIR/微信三开.app"

osacompile -o "$APP" -e '
try
    set runner to POSIX path of (path to resource "run.sh")
    do shell script "/bin/bash " & quoted form of runner
on error errMsg
    display dialog errMsg buttons {"好"} default button "好" with title "微信三开" with icon caution
end try
'
RESOURCES="$APP/Contents/Resources"
for file in sync_clones.py prepare_clone.py configure_clone_updates.sh; do
  cp "$SCRIPT_DIR/$file" "$RESOURCES/$file"
done
# 固定生成时的 Python 路径，避免 Finder 启动时 PATH 与终端不同。
printf '#!/bin/bash\nset -euo pipefail\nSCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"\nexec %q -B "$SCRIPT_DIR/sync_clones.py"\n' "$PYTHON_BIN" > "$RESOURCES/run.sh"
xcrun swiftc "$SCRIPT_DIR/clone_health.swift" -o "$RESOURCES/clone_health"
cp "/Applications/WeChat.app/Contents/Resources/AppIcon.icns" "$RESOURCES/applet.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
if [ -e "$TARGET_APP" ]; then
  mv "$TARGET_APP" "$BUILD_DIR/previous-launcher.app"
fi
if ! mv "$APP" "$TARGET_APP"; then
  if [ -e "$BUILD_DIR/previous-launcher.app" ]; then
    mv "$BUILD_DIR/previous-launcher.app" "$TARGET_APP"
  fi
  exit 1
fi
if [ -e "$BUILD_DIR/previous-launcher.app" ]; then
  /usr/bin/trash "$BUILD_DIR/previous-launcher.app"
fi
echo "已生成桌面微信三开：启动前自动检查并同步分身版本。"
