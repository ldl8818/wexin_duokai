# wexin_duokai

Mac 微信多开方案 · 一键升级脚本。

在一台 Mac 上同时跑多个微信账号（默认 3 个，可扩展），跟随 Mac App Store 主版本一起升级，**不丢任何聊天记录**。

## 文件索引

| 文件 | 用途 |
|---|---|
| [Mac多开微信.md](Mac多开微信.md) | 完整原理、SOP、故障排查、命名约定 |
| [升级分身.command](升级分身.command) | 主微信升级后，双击此脚本一键同步升级所有分身 |
| [生成三开微信App.command](生成三开微信App.command) | 双击生成桌面快捷启动器（自带微信图标），同时启动 3 个微信 |
| [configure_clone_updates.sh](configure_clone_updates.sh) | 禁止分身自动下载／安装更新；升级脚本在重签前调用 |
| [sync_clones.py](sync_clones.py) | 启动前版本比较、延后更新、应用替换及失败恢复 |
| [prepare_clone.py](prepare_clone.py) | 自动同步和手动升级共用的分身配置与签名 |
| [clone_health.swift](clone_health.swift) | 检查新分身完成启动并创建应用窗口；生成启动器时编译 |

## 核心原理（一句话）

macOS 把每个 App 的数据隔离在 `~/Library/Containers/<Bundle ID>/`。多开 = 克隆主微信、改 Bundle ID、重新签名。**聊天记录跟 Bundle ID 走**，与 App 文件名/位置无关。

详见 [Mac多开微信.md](Mac多开微信.md)。

## 快速开始

1. 已有主微信（App Store 装的 `WeChat.app`）
2. 下载本项目（`git clone` 或下载 zip）
3. 首次创建两个分身：在项目目录运行 `bash 升级分身.command --create-only`。该模式拒绝覆盖已有分身，不关闭主微信、不修改启动台。
4. 双击 `生成三开微信App.command` 生成桌面"微信三开.app"启动器；生成动作本身不创建分身。
5. 日常双击桌面启动器。它比较主微信与分身的版本号和构建号：同版本直接启动，主微信较新时自动同步，缺失分身则创建。直接打开分身 App 会跳过同步。

运行中的旧分身不会被关闭或替换，启动器会提示退出该分身后再打开启动器。新版先完成配置与签名验证，然后替换应用并启动；只有完成启动且持续10秒存在应用窗口，才清理旧程序。60秒内未通过则尝试退出新版、恢复并启动旧程序；若新版无法退出，保留备份，待退出分身后再次打开启动器恢复。启动窗口检查不等同于账号登录、收发和历史聊天验收。

自动升级的事务状态和临时旧程序在 `/Applications/.wechat-clone-update/`；不修改聊天容器，不降低较新分身的版本。程序回退只恢复 App，不回滚微信新版自行迁移过的聊天数据。不要同时运行手动升级命令与启动器。手动全量升级仍保留原来的流程，日常优先使用启动器。

启动器内嵌所需脚本和窗口检查程序，不依赖项目 `.tmp/` 或项目目录；依赖生成时找到的 Python 3 路径。安装 Python 的路径变化或更新本项目脚本后，重新生成启动器。生成步骤需要 Xcode Command Line Tools 的 `swiftc`。

回归验证：`python3 -B -m unittest -v test_sync_clones`，以及 `bash -n 升级分身.command 生成三开微信App.command configure_clone_updates.sh`。

4.1.15（270100）的创建流程还需保留主程序沙盒权限，并将应用身份和应用组映射为分身 ID。脚本先重签内嵌组件，再仅向最外层主程序应用权限；不要把主程序权限与 `codesign --deep` 一起使用。创建流程使用 `python3` 的标准库处理权限文件。

分身禁止自动下载和安装更新，通过上述脚本同步主微信版本。微信会在启动时重新开启版本检查，因此不能保证不检查或不提示新版本；不要在分身内手动安装更新。脚本同时设置应用默认值和用户偏好，主微信更新设置不受影响。单独运行更新策略脚本后必须重签名；一般直接使用完整升级入口。

策略使用 Sparkle 的 `SUAllowsAutomaticUpdates=false` 和 `SUAutomaticallyUpdate=false`。上游实现见 [SPUUpdaterSettings.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUUpdaterSettings.m)；微信内置框架可能有定制，最终以实际启动及跨更新周期检查为准。

> 第一次双击 `.command` 会被 macOS Gatekeeper 拦截：**右键 → 打开 → 打开** 即可一次性放行。

## 适用环境

- macOS（已测：15.7.3 Sequoia）
- 主微信由 Mac App Store 安装到 `/Applications/WeChat.app`

## 许可

MIT
