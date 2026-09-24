#!/usr/bin/env bash
# ============================================================================
# Mac 微信多开 · 一键升级分身
# ============================================================================
# 用途：主微信被 App Store 升级后，同步把分身升级到同样的版本，并保留所有
#       聊天记录、Bundle ID、容器路径不变。
# 用法：在 Finder 双击此文件即可（会自动用 Terminal 打开运行）。
# 配置：如果要修改分身数量，直接编辑下面的 N_CLONES 即可。
# 详细原理与故障排查：见同目录的 Mac多开微信.md
# ============================================================================

set -euo pipefail

CREATE_ONLY=0
case "${1:-}" in
  --create-only) CREATE_ONLY=1 ;;
  '') ;;
  *) echo '用法：bash 升级分身.command [--create-only]' >&2; exit 2 ;;
esac

# ---------- 配置 ----------
N_CLONES=2                       # 分身个数。本机当前 2 个（WeChat 2 + WeChat 3）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------- 常量 ----------
TS="$(date +%Y-%m-%d_%H%M%S)"
LP_BAK="$HOME/Documents/launchpad_db_$TS.bak"   # 启动台数据库备份（操作前留底）
LS="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PB="/usr/libexec/PlistBuddy"
MAIN_APP="/Applications/WeChat.app"
MAIN_ID="com.tencent.xinWeChat"

# ---------- 工具函数 ----------
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
phase()  { printf '\n\033[1;36m▶ [%s/8] %s\033[0m\n' "$1" "$2"; }

die() { red "❌ $*"; echo "脚本已停止。按任意键退出…"; read -n1; exit 1; }

# ---------- 起手检查 ----------
if [ -t 1 ]; then clear; fi
bold "════════════════════════════════════════════"
bold "  Mac 微信多开 · 一键升级分身"
bold "════════════════════════════════════════════"
echo

[ -d "$MAIN_APP" ] || die "找不到主微信 $MAIN_APP"
[ -f "$SCRIPT_DIR/configure_clone_updates.sh" ] || die "缺少分身更新策略脚本"

MAIN_VER=$($PB -c "Print :CFBundleShortVersionString" "$MAIN_APP/Contents/Info.plist")
echo "主微信版本: $MAIN_VER"
echo "分身个数:   ${N_CLONES}（WeChat 2 ~ WeChat $((N_CLONES+1))）"
echo
if [ "$CREATE_ONLY" -eq 0 ]; then
echo "本工具会："
echo "  1) 关闭所有微信进程（请先确保没在传重要文件）"
echo "  2) 删除旧分身 App（沙盒容器/聊天记录不删 —— 这是聊天记录的保护铁律）"
echo "  3) 从主微信 v$MAIN_VER 克隆 $N_CLONES 个新分身"
echo "  4) 改 Bundle ID + 显示名 + 重签名 + 注册到系统"
echo "  5) 修复启动台显示"
echo
yellow "ℹ️ 聊天记录在 ~/Library/Containers/${MAIN_ID}.clone*/，本流程全程不动该目录，"
yellow "  因此默认不备份（4G 时间空间成本不值）。仅备份启动台数据库（7MB）。"
fi
echo
if [ "$CREATE_ONLY" -eq 1 ]; then
  for n in $(seq 2 $((N_CLONES+1))); do
    [ ! -e "/Applications/WeChat $n.app" ] || { echo "分身已存在，拒绝覆盖：WeChat $n.app" >&2; exit 1; }
  done
  echo '仅创建模式：不关闭微信、不删除应用、不改启动台。'
  yn=y
else
read -p "确认开始？输 y 继续，其他键退出: " yn
fi
[[ "$yn" =~ ^[Yy]$ ]] || { echo "已取消。"; exit 0; }

if [ "$CREATE_ONLY" -eq 0 ]; then
# ---------- Phase 1: 关闭微信进程 ----------
phase 1 "关闭所有微信进程"
pkill -TERM -f "WeChatAppEx"                 2>/dev/null || true
pkill -TERM -f "/Applications/WeChat.*\.app" 2>/dev/null || true
pkill -TERM -f "wxutility|wxplayer|wxocr"    2>/dev/null || true
sleep 4
remain=$(ps aux | grep -iE "/Applications/WeChat" | grep -v grep | grep -v WeWork | wc -l | tr -d ' ')
if [ "$remain" -gt 0 ]; then
  yellow "  ⚠️ SIGTERM 后仍有 $remain 个进程残留，发 SIGKILL …"
  pkill -KILL -f "WeChat" 2>/dev/null || true
  pkill -KILL -f "wxutility|wxplayer|wxocr" 2>/dev/null || true
  sleep 2
fi
green "  ✅ 所有微信进程已退出"

# ---------- Phase 2: 删除旧分身 App ----------
phase 2 "删除旧分身 App"
NEED_SUDO=0
for n in $(seq 2 $((N_CLONES+1))); do
  app="/Applications/WeChat $n.app"
  if [ -d "$app" ]; then
    owner=$(stat -f "%Su" "$app")
    if [ "$owner" != "$(whoami)" ]; then NEED_SUDO=1; fi
  fi
done

if [ $NEED_SUDO -eq 1 ]; then
  yellow "  ⚠️ 检测到 root 拥有的旧 App，需要管理员权限改所有权"
  echo "     接下来会弹出 macOS 密码框，输入你的登录密码"
  CHOWN_TARGETS=""
  for n in $(seq 2 $((N_CLONES+1))); do
    app="/Applications/WeChat $n.app"
    [ -d "$app" ] && CHOWN_TARGETS="$CHOWN_TARGETS \"$app\""
  done
  osascript -e "do shell script \"chown -R $(whoami):admin $CHOWN_TARGETS\" with administrator privileges with prompt \"微信多开升级：转所有权\""
fi

for n in $(seq 2 $((N_CLONES+1))); do
  app="/Applications/WeChat $n.app"
  if [ -d "$app" ]; then
    trash "$app"
    echo "  ✅ $app → 废纸篓"
  fi
done
# 顺手 trash 可能存在的"跳转 shim"或"Core"等历史残留
for legacy in "/Applications/WeChat 2 Core.app" "/Applications/WeChat 3 Core.app"; do
  [ -d "$legacy" ] && trash "$legacy" && echo "  ✅ $legacy → 废纸篓（历史残留）"
done

# ---------- Phase 3: 克隆新版分身 ----------
fi
phase 3 "从主版本克隆 $N_CLONES 个新分身"
for n in $(seq 2 $((N_CLONES+1))); do
  echo "  克隆 → WeChat $n.app …"
  ditto "$MAIN_APP" "/Applications/WeChat $n.app"
done
green "  ✅ 克隆完成"

# ---------- Phase 4/5: 共享配置与签名 ----------
phase 4 "配置分身身份、本地化名称和更新策略"
for n in $(seq 2 $((N_CLONES+1))); do
  app="/Applications/WeChat $n.app"
  python3 -B "$SCRIPT_DIR/prepare_clone.py" "$MAIN_APP" "$app" "$n"
  "$LS" -f "$app"
  echo "  ✅ WeChat $n.app 配置与签名验证通过"
done

# 仅升级模式清理旧注册；首次创建不扫描无关旧应用。
if [ "$CREATE_ONLY" -eq 0 ]; then
echo "  清理废纸篓里旧 App 的 LaunchServices 残留 …"
find "$HOME/.Trash" -maxdepth 1 -name "WeChat*.app" -print0 2>/dev/null \
  | xargs -0 -I {} "$LS" -u "{}" 2>/dev/null || true
fi

# ---------- Phase 6: 修复启动台显示 ----------
if [ "$CREATE_ONLY" -eq 0 ]; then
phase 6 "修复启动台显示（如有需要）"
LP_DB="$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db"
if [ -f "$LP_DB" ]; then
  cp "$LP_DB" "$LP_BAK"
  echo "  Launchpad DB 已备份 → $LP_BAK"

  for n in $(seq 2 $((N_CLONES+1))); do
    bid="${MAIN_ID}.clone$n"
    rowid=$(sqlite3 "$LP_DB" "SELECT item_id FROM apps WHERE bundleid='$bid';" || true)
    if [ -z "$rowid" ]; then
      echo "  ⚠️ Launchpad 数据库尚无 ${bid}，下次重启 Dock 后会自动出现"
      continue
    fi

    # 把每个新分身的 bundleid 字段强 UPDATE 一次（防止某些步骤里漏改）
    sqlite3 "$LP_DB" "UPDATE apps SET bundleid='$bid' WHERE item_id=$rowid;"

    # 检查它的 parent 链是否汇到主 root（rowid=1）
    in_main=$(sqlite3 "$LP_DB" "
      WITH RECURSIVE chain(id, pid) AS (
        SELECT rowid, parent_id FROM items WHERE rowid=$rowid
        UNION ALL
        SELECT i.rowid, i.parent_id FROM items i JOIN chain c ON i.rowid=c.pid
        WHERE c.pid > 0
      )
      SELECT EXISTS(SELECT 1 FROM chain WHERE id=1);
    ")

    if [ "$in_main" = "1" ]; then
      echo "  ✅ $bid 已在主 root 下"
    else
      # 不在主 root → 找一个"app 数最少"的 page，追加到它末尾
      target=$(sqlite3 "$LP_DB" "
        SELECT p.rowid || '|' || (COALESCE(MAX(c.ordering),-1) + 1)
        FROM items p LEFT JOIN items c ON c.parent_id = p.rowid
        WHERE p.parent_id = 1 AND p.type = 3
        GROUP BY p.rowid
        ORDER BY COUNT(c.rowid) ASC, p.ordering ASC
        LIMIT 1;
      ")
      page_id=${target%|*}
      next_ord=${target#*|}
      sqlite3 "$LP_DB" "UPDATE items SET parent_id=$page_id, ordering=$next_ord WHERE rowid=$rowid;"
      green "  ✅ $bid 已迁移到主 root (page $page_id, ordering $next_ord)"
    fi
  done

  sqlite3 "$LP_DB" "PRAGMA wal_checkpoint(FULL);"
else
  yellow "  ⚠️ 找不到 Launchpad 数据库（macOS 版本可能不同），跳过"
fi

# ---------- Phase 7: 重启 Dock + Finder ----------
phase 7 "刷新 Dock 和 Finder"
killall Dock   2>/dev/null || true
killall Finder 2>/dev/null || true
green "  ✅ Dock 已重启（启动台布局不变）"
fi

# ---------- Phase 8: 验证 ----------
phase 8 "终态验证"
echo
echo "应用、Bundle ID、容器、版本一致性："
for n in 0 $(seq 2 $((N_CLONES+1))); do
  if [ "$n" = "0" ]; then
    app="$MAIN_APP"; label="主微信"
  else
    app="/Applications/WeChat $n.app"; label="WeChat $n"
  fi
  if [ -d "$app" ]; then
    id=$($PB -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null)
    ver=$($PB -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist" 2>/dev/null)
    csz=$(du -sh "$HOME/Library/Containers/$id" 2>/dev/null | cut -f1 || true)
    printf "  · %-12s v%-6s · %s · 容器 %s\n" "$label" "$ver" "$id" "${csz:-?}"
  fi
done

echo
green "════════════════════════════════════════════"
green "  应用创建和签名检查完成，仍须验证真实启动！"
green "════════════════════════════════════════════"
echo
echo "📋 请你做："
echo "  1) 按 F4 或四指捏合打开启动台，检查能看到微信 / 微信 2 / 微信 3"
echo "  2) 启动每个分身确认聊天记录都在"
echo
if [ "$CREATE_ONLY" -eq 0 ]; then
echo "🗂  启动台 DB 备份: ${LP_BAK}（确认无问题后可 trash）"
fi
echo
echo "如果启动台还看不到分身，参考 Mac多开微信.md 的"故障排查"章节。"
echo
echo "按任意键退出…"
if [ -t 0 ]; then read -n1; fi
