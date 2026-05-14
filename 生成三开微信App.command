#!/bin/bash
# ============================================================================
# 生成「微信三开」启动器 App（带微信图标，无终端窗口）
# ============================================================================
# 双击此文件一次，会在桌面生成 ~/Desktop/微信三开.app
# 之后日常使用：双击桌面那个 .app 即可同时打开 3 个微信
# 如果以后改名了分身（例如改成 4 开），编辑下面的 AppleScript 增加几行即可
# ============================================================================

# 在桌面建一个快捷启动按钮：
TARGET_APP=~/Desktop/微信三开.app

echo "正在编译 AppleScript 为应用程序..."

# 1. 使用 osacompile 编译为 .app (这是核心)
# 使用 AppleScript 语法，不会弹出终端窗口
osacompile -o "$TARGET_APP" -e '
try
    do shell script "open -a \"/Applications/WeChat.app\""
    delay 0.5
    do shell script "open -a \"/Applications/WeChat 2.app\""
    delay 0.5
    do shell script "open -a \"/Applications/WeChat 3.app\""
on error errMsg
    display dialog "启动出错: " & errMsg buttons {"OK"} default button "OK" with icon stop
end try
'

echo "正在注入原版微信图标..."

# 2. 偷天换日：提取原版微信图标并覆盖新 App 的图标
# 注意：AppleScript 编译出的 app 图标名叫 applet.icns
cp "/Applications/WeChat.app/Contents/Resources/AppIcon.icns" "$TARGET_APP/Contents/Resources/applet.icns"

# 3. 刷新图标缓存 (让系统立刻识别新图标)
touch "$TARGET_APP"

echo "---------------------------------------"
echo "✅ 搞定！桌面已生成【微信三开】App"
echo "✨ 图标已自动替换为微信图标"
echo "💡 你现在可以把它拖到 Dock 栏固定了"
echo "---------------------------------------"
