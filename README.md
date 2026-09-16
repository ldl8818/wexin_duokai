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

## 核心原理（一句话）

macOS 把每个 App 的数据隔离在 `~/Library/Containers/<Bundle ID>/`。多开 = 克隆主微信、改 Bundle ID、重新签名。**聊天记录跟 Bundle ID 走**，与 App 文件名/位置无关。

详见 [Mac多开微信.md](Mac多开微信.md)。

## 快速开始

1. 已有主微信（App Store 装的 `WeChat.app`）
2. 下载本项目（`git clone` 或下载 zip）
3. 双击 `生成三开微信App.command` 生成桌面"微信三开.app"启动器
4. 主微信日后升级时，双击 `升级分身.command` 同步升级分身

分身禁止自动下载和安装更新，通过上述脚本同步主微信版本。微信会在启动时重新开启版本检查，因此不能保证不检查或不提示新版本；不要在分身内手动安装更新。脚本同时设置应用默认值和用户偏好，主微信更新设置不受影响。单独运行更新策略脚本后必须重签名；一般直接使用完整升级入口。

策略使用 Sparkle 的 `SUAllowsAutomaticUpdates=false` 和 `SUAutomaticallyUpdate=false`。上游实现见 [SPUUpdaterSettings.m](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUUpdaterSettings.m)；微信内置框架可能有定制，最终以实际启动及跨更新周期检查为准。

> 第一次双击 `.command` 会被 macOS Gatekeeper 拦截：**右键 → 打开 → 打开** 即可一次性放行。

## 适用环境

- macOS（已测：15.7.3 Sequoia）
- 主微信由 Mac App Store 安装到 `/Applications/WeChat.app`

## 许可

MIT
