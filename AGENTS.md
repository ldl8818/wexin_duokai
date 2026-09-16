# 项目约定

- 本项目维护主微信加两个独立 Bundle ID 分身的创建与升级；现有 `.command` 文件名保持不变。
- 主微信仅作为复制来源；分身使用 `com.tencent.xinWeChat.clone<N>`，N 从2开始。
- 不修改或删除聊天记录容器。分身禁止 Sparkle 自动下载和安装，只通过升级脚本从主微信同步版本；微信会在启动时开启版本检查，不把偏好键静态值当作禁止检查的证明。
- `configure_clone_updates.sh` 是分身更新策略的唯一实现，调用后必须重签名并验证签名。
- 验证入口：`bash -n` 检查脚本语法，核对分身 Bundle ID、更新设置和 `codesign --verify --deep --strict`；真实启动另行记录，不用静态检查代替。
