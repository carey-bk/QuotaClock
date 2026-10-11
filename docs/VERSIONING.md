# 版本与更新

版本唯一来源为 `project.yml` 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。
本次准备版本为 1.2.0，内部构建号 96；这不是发布声明。

- 正式版本采用 MAJOR.MINOR.PATCH；主版本用于重大架构变化，次版本用于新增功能，修订版本用于修复。
- 修改 project.yml 后运行 `xcodegen generate`。App、Widget、Saver 的 Info.plist 均引用构建设置，UI 从 Bundle 读取并显示 v 前缀。普通界面不显示 Build，复制诊断信息保留 Build。
- 正式打包不要使用命令行版本覆盖。`Scripts/package-update.py` 会检查产物与 project.yml 一致，并生成 vMAJOR.MINOR.PATCH 的 GitHub 下载路径。它不创建或修改 Release。
- Sparkle appcast 继续保留递增 Build，以兼容旧客户端；shortVersionString 为三段式正式版本。发布新版本时两者都要递增。旧 Release 和 Tag 不改动。
- 新客户端将历史 appcast Build 映射到 shortVersionString 后按数字比较。兼容 v 前缀、旧两段版本及 beta/build 后缀。相同三段版本视为相同，不因内部 Build 或 beta 后缀重复提示更新；更新的开发版本不降级。
- 没有可解析正式版本的条目不推荐安装；不会把任意时间戳当成正式版本。
- 手动检查通过 Sparkle 信息检查完成后显示中文结果；用户点击“查看更新”进入 Sparkle 原生更新说明、下载、签名验证和安装流程。Sparkle 自身安装界面的语言遵循系统本地化。
- 后台检查采用 Sparkle gentle reminders，在设置页显示可用版本，不弹窗，不自动下载。

验证：`swift test`，`python3 Scripts/check-updater-feed.py`，Release xcodebuild，`python3 Scripts/check-updater-bundle.py build.noindex/Build/Products/Release/QuotaClock.app`。
Feed 测试仅使用本机临时 HTTP 服务与临时应用，不下载或安装更新。
