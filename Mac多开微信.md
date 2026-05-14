# Mac 微信多开方案

> **目标读者**：本机用户野肆、未来的 AI 助手、其他人。
> **目标**：照着这份文档，**10 分钟内**完成"首次部署"或"主版本升级时同步升级分身"，且**不丢任何聊天记录**。
> **当前部署**：3 个微信（1 主 + 2 分身），跟随 Mac App Store 主版本升级。
> **最近一次升级**：2026-05-14（主版本 4.1.9）。

## 🚀 快捷脚本（优先使用）

本目录自带两个开箱即用的 `.command` 脚本，双击即可运行——**先用脚本，不行再看下面的 SOP**：

| 脚本 | 用途 |
|---|---|
| `升级分身.command` | 主微信升级后，双击此文件一键升级所有分身（备份 → 关进程 → 删旧 → 克隆 → 改 ID + 显示名 → 重签 → 注册 → 修启动台，全自动）。配置分身数量编辑脚本顶部 `N_CLONES`。 |
| `生成三开微信App.command` | 双击一次生成桌面快捷启动器 `~/Desktop/微信三开.app`（自带微信图标）。之后双击桌面那个 .app 即可同时启动 3 个微信。 |

> 第一次运行 `.command` 文件如果系统提示"无法验证开发者"：右键 → 打开 → 选"打开"。
> 脚本失效、想理解原理、或需要手工排查时，往下看完整章节。

---

## 一句话原理

macOS 把每个 App 的数据隔离在沙盒目录 `~/Library/Containers/<Bundle ID>/`。两个 App 只要 **Bundle ID 不同**，就各自有独立沙盒，账号与聊天记录互不干扰。

所以多开 = **克隆主微信 App，改 Bundle ID，重新签名**。

**🔑 最重要的一句话（背下来）**：聊天记录跟 **Bundle ID 走**，不跟 App 文件名/位置走。换 App、删 App、重新克隆都不会动数据——只要 Bundle ID 不变，新 App 启动后自动接管原沙盒。

---

## 当前部署状态

| 应用文件 | Bundle ID | 沙盒容器（聊天记录所在） |
|---|---|---|
| `/Applications/WeChat.app` | `com.tencent.xinWeChat` | `~/Library/Containers/com.tencent.xinWeChat/` |
| `/Applications/WeChat 2.app` | `com.tencent.xinWeChat.clone2` | `~/Library/Containers/com.tencent.xinWeChat.clone2/` |
| `/Applications/WeChat 3.app` | `com.tencent.xinWeChat.clone3` | `~/Library/Containers/com.tencent.xinWeChat.clone3/` |

**命名约定**（**未来扩展时务必遵守**）：
- App 文件名：`WeChat <N>.app`（数字前留一个空格）
- Bundle ID：`com.tencent.xinWeChat.clone<N>`
- 显示名：中文 `微信 <N>` / 英文 `WeChat <N>`
- N 从 2 开始递增

> 历史教训：之前用过三种命名（`xinWeChat2` / `xin.wechat2` / `xinWeChat.clone2` 共存），导致容器残留满天飞。统一用 `.clone<N>` 后才干净。**新增分身一定走这个命名约定。**

---

## 升级 SOP（主微信被 App Store 升级后，同步升级分身）

主微信跟着 App Store 自动升级，**分身 App 不会自动跟随**——分身只是主程序的克隆副本，主版本升级后分身仍停留在旧版。

下面是一次完整升级的全流程。**预计耗时 10 分钟**（其中备份占大头）。

> ⚠️ **执行前先确认**：主微信已经升级到目标版本（`defaults read /Applications/WeChat.app/Contents/Info.plist CFBundleShortVersionString` 看版本号）。

### Phase 1 — 备份聊天记录（保命）

```bash
# 备份时间戳目录
BACKUP="$HOME/Documents/微信备份_$(date +%Y-%m-%d)"
mkdir -p "$BACKUP"

# 用 ditto 完整复制（保留沙盒权限、扩展属性，比 cp 安全）
ditto "$HOME/Library/Containers/com.tencent.xinWeChat.clone2" "$BACKUP/com.tencent.xinWeChat.clone2"
ditto "$HOME/Library/Containers/com.tencent.xinWeChat.clone3" "$BACKUP/com.tencent.xinWeChat.clone3"

# 备份完核对大小
du -sh "$BACKUP"
```

### Phase 2 — 关闭所有微信进程

```bash
pkill -TERM -f "WeChatAppEx" 2>/dev/null
pkill -TERM -f "WeChat\.app"  2>/dev/null
pkill -TERM -f "wxutility|wxplayer|wxocr" 2>/dev/null
sleep 4
# 验证全部退出
ps aux | grep -iE "WeChat" | grep -v grep | grep -v WeWork
```

### Phase 3 — 删除旧分身 App（保留沙盒容器！）

```bash
# 如果旧 App 是 root 拥有的（之前某些方案会导致这种情况），先弹密码框把所有权改回 dylan
osascript -e 'do shell script "chown -R dylan:admin \"/Applications/WeChat 2.app\" \"/Applications/WeChat 3.app\"" with administrator privileges with prompt "微信多开升级：转所有权"'

# trash 而非 rm（保留废纸篓恢复能力）
trash "/Applications/WeChat 2.app"
trash "/Applications/WeChat 3.app"
```

> ⚠️ **绝对不要**删 `~/Library/Containers/com.tencent.xinWeChat.clone*` —— 那是聊天记录。

### Phase 4 — 从新版主程序克隆分身

```bash
# 必须用 ditto，不能用 cp -R（会跟随符号链接破坏 App bundle）
ditto "/Applications/WeChat.app" "/Applications/WeChat 2.app"
ditto "/Applications/WeChat.app" "/Applications/WeChat 3.app"
```

### Phase 5 — 改 Bundle ID + 显示名

**关键陷阱**：微信内部有**本地化字符串文件**（`zh-Hans.lproj/InfoPlist.strings`），中文系统会优先用它显示名字。只改 `Info.plist` 的 `CFBundleDisplayName` 没用——必须把 3 种语言的本地化字符串都改。

```bash
PB=/usr/libexec/PlistBuddy

# 改一个分身的所有相关字段
patch_app() {
  local app="$1"        # "WeChat 2"
  local clone_n="$2"    # "2"

  local info="/Applications/$app.app/Contents/Info.plist"
  $PB -c "Set :CFBundleIdentifier com.tencent.xinWeChat.clone$clone_n" "$info"
  $PB -c "Set :CFBundleName $app" "$info"
  $PB -c "Set :CFBundleDisplayName $app" "$info" 2>/dev/null || $PB -c "Add :CFBundleDisplayName string $app" "$info"

  # 本地化字符串（中文显示名靠这个）
  for lproj in zh-Hans zh-Hant; do
    f="/Applications/$app.app/Contents/Resources/$lproj.lproj/InfoPlist.strings"
    $PB -c "Set :CFBundleDisplayName 微信 $clone_n" "$f"
    $PB -c "Set :CFBundleName 微信 $clone_n" "$f"
  done
  f="/Applications/$app.app/Contents/Resources/en.lproj/InfoPlist.strings"
  $PB -c "Set :CFBundleDisplayName $app" "$f"
  $PB -c "Set :CFBundleName $app" "$f"
}

patch_app "WeChat 2" 2
patch_app "WeChat 3" 3
```

### Phase 6 — adhoc 重签 + 注册到系统

```bash
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

for app in "WeChat 2" "WeChat 3"; do
  # 清扩展属性（quarantine 等）
  xattr -dr com.apple.quarantine "/Applications/$app.app" 2>/dev/null || true
  # adhoc 重签（必须，否则新 Bundle ID 跟 App Store 原签名冲突）
  codesign --force --deep --sign - "/Applications/$app.app"
  # 注册到 LaunchServices（让 Spotlight / Launchpad 看到）
  "$LS" -f "/Applications/$app.app"
done

# 顺便从 LS 清理废纸篓里的旧 App（防止与新 App 抢同一 Bundle ID）
find "$HOME/.Trash" -maxdepth 1 -name "WeChat*.app" -print0 | xargs -0 -I {} "$LS" -u "{}" 2>/dev/null
```

### Phase 7 — 验证

```bash
# 1. Bundle ID & 容器对得上
for app in "WeChat" "WeChat 2" "WeChat 3"; do
  id=$(defaults read "/Applications/$app.app/Contents/Info.plist" CFBundleIdentifier)
  ver=$(defaults read "/Applications/$app.app/Contents/Info.plist" CFBundleShortVersionString)
  echo "$app.app → v$ver · ID $id · 容器 $(du -sh "$HOME/Library/Containers/$id" 2>/dev/null | cut -f1)"
done

# 2. 签名有效
for app in "WeChat" "WeChat 2" "WeChat 3"; do
  codesign --verify "/Applications/$app.app" && echo "✅ $app.app 签名有效"
done

# 3. 手动启动分身：Finder → 应用程序 → 双击 WeChat 2.app / WeChat 3.app
#    确认登录态保留、聊天记录完整。
```

### Phase 8 — 让启动台显示新分身（关键，新手必踩）

**默认情况下，刚克隆并改完 Bundle ID 的分身，Launchpad（启动台）大概率不显示。**这是一类独立问题，见下一节"故障排查"。

---

## 故障排查：启动台不显示新分身

### 症状
- `/Applications/` 里能看到 `WeChat 2.app` / `WeChat 3.app`
- Finder 能启动它们
- **但启动台（Launchpad，F4 / 四指捏合手势）找不到**

### 根因（按概率排序）

#### A. LaunchServices 数据库里同一 Bundle ID 注册了多条路径

**查诊**：
```bash
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LS" -dump | grep -A1 "xinWeChat\.clone"
```

如果同一 Bundle ID 同时指向 `/Applications/...` 和 `~/.Trash/...`，Launchpad 会因歧义干脆不显示。

**修复**：清理废纸篓里旧 App 在 LS 的注册，重新强制注册新 App。
```bash
find "$HOME/.Trash" -maxdepth 1 -name "WeChat*.app" -print0 | xargs -0 -I {} "$LS" -u "{}"
"$LS" -f "/Applications/WeChat 2.app" "/Applications/WeChat 3.app"
killall Dock
```

#### B. Launchpad SQLite 把新 App 误放到"孤立 root"

macOS Launchpad 的数据库（SQLite）里有时存在**两个 type=1 的 root 节点**：
- `rowid=1` 是**主 root**，下挂用户能看到的所有 page
- `rowid=5` 是**隐藏 root**（用途不明，可能历史遗留），下挂的 App 永远不渲染

如果新克隆的 App 被错误地分配到 `rowid=5` 下，启动台永远看不到，不管你怎么刷 Dock 都没用。

**Launchpad 数据库位置**：
```bash
LP_DB="$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db"
```

**查诊**（找出新 App 在数据库里的位置）：
```bash
sqlite3 -header -column "$LP_DB" "
  SELECT i.rowid, i.type, i.parent_id, i.ordering, a.title, a.bundleid
  FROM items i JOIN apps a ON a.item_id = i.rowid
  WHERE a.bundleid LIKE '%xinWeChat.clone%';"
```

如果新 App 的 `parent_id` 链最终指向 `rowid=5` 而不是 `rowid=1`，就是这个问题。验证：
```bash
sqlite3 "$LP_DB" "WITH RECURSIVE chain(rowid, parent_id, depth) AS (
  SELECT rowid, parent_id, 0 FROM items WHERE rowid=<新App的rowid>
  UNION ALL
  SELECT i.rowid, i.parent_id, c.depth+1 FROM items i JOIN chain c ON i.rowid=c.parent_id
  WHERE c.parent_id IS NOT NULL AND c.depth < 10
) SELECT * FROM chain;"
```

**修复**：把新 App 迁移到主 root 下的某一页。

第一步：找出主 root 下哪一页有空位（不要打乱已有图标）：
```bash
sqlite3 -header -column "$LP_DB" "
  SELECT p.rowid AS page_id, p.ordering AS page_idx, COUNT(c.rowid) AS app_count
  FROM items p LEFT JOIN items c ON c.parent_id = p.rowid
  WHERE p.parent_id = 1 AND p.type = 3
  GROUP BY p.rowid ORDER BY p.ordering;"
```

第二步：**操作前一定先备份数据库**：
```bash
cp "$LP_DB" "$HOME/Documents/launchpad_db.bak.$(date +%s)"
```

第三步：把新 App 移到目标 page 的末尾。例：把 rowid=222 移到 page rowid=2，ordering=0：
```bash
sqlite3 "$LP_DB" "UPDATE items SET parent_id=2, ordering=0 WHERE rowid=222;"
sqlite3 "$LP_DB" "PRAGMA wal_checkpoint(FULL);"
killall Dock
```

#### C. SQLite WAL 没落盘（Dock 启动时读到旧数据）

每次改完 Launchpad 数据库后，强制 checkpoint：
```bash
sqlite3 "$LP_DB" "PRAGMA wal_checkpoint(FULL);"
killall Dock
```

---

## 不要这样做（踩过的坑）

| ❌ 错误做法 | ⚠️ 后果 | ✅ 正确做法 |
|---|---|---|
| `cp -R WeChat.app WeChat\ 2.app` | App bundle 内符号链接被跟随、损坏 | `ditto WeChat.app "WeChat 2.app"` |
| `rm -rf ~/Library/Containers/com.tencent.xinWeChat.clone2` | **聊天记录永久丢失** | `trash` 移到废纸篓 |
| `defaults write com.apple.dock ResetLaunchPad -bool true && killall Dock` | 启动台所有图标排列重置回字母序 | 用 SQLite UPDATE 精准改单行 |
| 只改 `Info.plist` 的 `CFBundleDisplayName` | 中文系统 Finder 仍显示"微信"（本地化字符串覆盖） | 同时改 zh-Hans / zh-Hant / en 的 `InfoPlist.strings` |
| 用"跳转 applet"间接启动分身 | 多一层 99KB 中间程序，升级时还得维护 | 直接把分身 App 命名为 `WeChat <N>.app` |
| 触碰 `com.tencent.xinWeChat.WeChatFileProviderExtension` / `.WeChatMacShare` | 破坏系统级集成 | 不动它们，跟多开无关 |

---

## 附录 A：从备份还原聊天记录

如果某次升级后聊天记录丢失或损坏，从备份恢复：

```bash
# 先关掉对应分身
pkill -TERM -f "/Applications/WeChat 2.app"
sleep 3

# 删坏掉的容器
trash "$HOME/Library/Containers/com.tencent.xinWeChat.clone2"

# 从备份还原
ditto "$HOME/Documents/微信备份_<日期>/com.tencent.xinWeChat.clone2" \
      "$HOME/Library/Containers/com.tencent.xinWeChat.clone2"

# 重新启动分身
open "/Applications/WeChat 2.app"
```

## 附录 B：彻底清理（卸载某个分身）

```bash
N=3   # 要删除的分身编号
trash "/Applications/WeChat $N.app"
trash "$HOME/Library/Containers/com.tencent.xinWeChat.clone$N"
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LS" -u "/Applications/WeChat $N.app" 2>/dev/null
killall Dock
```

## 附录 C：扩展第 4 个分身（首次创建新分身）

照搬升级 SOP 的 Phase 4-7，把 N=4 套进去即可。注意此时 `~/Library/Containers/com.tencent.xinWeChat.clone4` 还不存在，**新分身首次启动时会自动创建容器并要求扫码登录**——和正常微信首次登录一致。

---

## 附录 D：关键路径速查

| 用途 | 路径 |
|---|---|
| App 安装位置 | `/Applications/WeChat*.app` |
| 沙盒容器（聊天记录） | `~/Library/Containers/com.tencent.xinWeChat<.cloneN>/` |
| LaunchServices 工具 | `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister` |
| Launchpad SQLite | `$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` |
| plist 编辑工具 | `/usr/libexec/PlistBuddy` |

---

## 修订记录

- **2026-05-14** 主版本升级到 4.1.9，同步升级分身。去掉旧的"跳转 applet"方案，统一改用 `WeChat <N>.app` 直接命名。清理历史残留容器（`xinWeChat2`、`xin.wechat2`、`xinWeChat3`）。修复启动台不显示问题（Launchpad SQLite 双 root → 迁移到主 root 的空页）。本文档**首次写就**，并把整个流程沉淀为 `升级分身.command` + `生成三开微信App.command` 两个一键脚本。
