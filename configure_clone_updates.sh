#!/usr/bin/env bash
# Only configure a clone; the caller must re-sign it after modifying Info.plist.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "用法：bash configure_clone_updates.sh '/Applications/WeChat 2.app'" >&2
  exit 2
fi

app="$1"
info="$app/Contents/Info.plist"
pb=/usr/libexec/PlistBuddy
bundle_id=$("$pb" -c 'Print :CFBundleIdentifier' "$info")
if [[ ! "$bundle_id" =~ ^com\.tencent\.xinWeChat\.clone([2-9]|[1-9][0-9]+)$ ]]; then
  echo "拒绝修改：目标不是有效的微信分身。" >&2
  exit 2
fi

# WeChat enables version checks in code at launch. These two Sparkle settings
# prevent automatic downloads/installation without relying on that check switch.
for key in SUAutomaticallyUpdate SUAllowsAutomaticUpdates; do
  if "$pb" -c "Print :$key" "$info" >/dev/null 2>&1; then
    "$pb" -c "Set :$key false" "$info"
  else
    "$pb" -c "Add :$key bool false" "$info"
  fi
  /usr/bin/defaults write "$bundle_id" "$key" -bool false
  [ "$("$pb" -c "Print :$key" "$info")" = false ]
  [ "$(/usr/bin/defaults read "$bundle_id" "$key")" = 0 ]
done
printf '%s：已禁止自动下载和安装更新；微信仍可能检查版本。\n' "$bundle_id"
