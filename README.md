# QuotaClock

**AI 额度，一眼掌握。** 为 macOS 打造的原生额度监控工具，在菜单栏、桌面小组件和屏幕保护程序中查看 AI 服务的剩余额度与余额。

[产品介绍](https://carey-bk.github.io/QuotaClock/) · [下载安装包](https://github.com/carey-bk/QuotaClock/releases/latest)

## 功能

- **三个展示入口**：可配置的菜单栏面板、WidgetKit 小组件和原生 `.saver` 屏保。
- **多服务、多账户**：Codex 多账户、Claude Code、本地 CLI 和受支持的 API 服务接入；实际数据以各服务可用能力为准。
- **统一管理**：在「AI 服务」中调整顺序与 Hero；菜单栏和屏保分别控制各服务是否显示。
- **Auto Hero**：优先展示所选 Hero 服务商当前登录的账户；关闭后遵循自定义顺序。
- **个性化**：浅色、深色、跟随系统，两种应用图标，仪表盘或服务商菜单栏图标。
- **Codex 账户切换**：保存当前登录、切换凭据并重新打开 Codex。切换会中断正在运行的任务，请先结束任务。

## 安装

1. 从 Releases 下载 DMG，将 QuotaClock 拖到 Applications。
2. 双击 `QuotaClock.saver`，按系统提示安装。
3. 打开应用，完成引导并添加服务商。独立登录保存凭据用于持续监控；关联当前会话只读取本机登录状态。
4. 在 macOS 系统设置中选用 QuotaClock 屏保。安装 `.saver` 本身不会自动将其设为当前屏保。
5. 桌面小组件通过 macOS 的「编辑小组件」添加。

当前版本 **1.0.0 (80)**，安装包包含 Apple Silicon 与 Intel 架构，使用 Developer ID 签名；尚未完成 Apple 公证。源码部署目标为 macOS 14+，各系统展示能力与表现可能不同。

## 应用内更新

在「关于」或应用菜单选择「检查更新」。默认每天检查一次轻量更新清单，确认后才下载；可关闭自动检查。应用与小组件一起更新。独立屏保请在「关于 → 安装或更新屏幕保护程序」中更新，系统可能要求管理员验证。

0.x 没有更新器，需要手动安装一次 1.0。此后使用 Sparkle 校验签名并安装正式版更新。发布维护流程见 [更新发布指南](docs/UPDATES.md)。

## 构建与测试

需要 Xcode、Swift 工具链。工程已生成；修改 `project.yml` 后使用 XcodeGen 重新生成。

```sh
swift test
bash Scripts/prepare-sparkle.sh
xcodebuild -project QuotaClock.xcodeproj -scheme QuotaClock \
  -configuration Debug -derivedDataPath build.noindex build
```

分发签名需要自己的 Apple Developer 团队、证书、App Group 及相应 entitlements；仓库中的团队标识仅用于原作者构建，不包含签名私钥。纯 QuotaCore 测试无需分发证书。

## 数据与边界

主应用负责获取数据；菜单栏、小组件与屏保消费本地快照。独立登录凭据保存在 macOS 钥匙串中。数据缺失或失效时显示相应状态，不生成虚假额度。WidgetKit 刷新时机由 macOS 决定，不能保证即时更新。

本项目处于持续迭代阶段，不是 OpenAI、Anthropic 或其他服务商的官方产品。第三方标志及字体的许可见 `Assets/LobeIcons-LICENSE` 和 `Assets/Fonts` 中的许可文件。本仓库目前未授予项目整体的开源许可证。

## 目录

- `Sources/QuotaCore`：数据模型、接入与快照逻辑。
- `Sources/QuotaClockApp`：macOS 设置与菜单栏应用。
- `Sources/QuotaWidget`、`Sources/QuotaSaver`：系统展示扩展。
- `site/dist`：无构建依赖的产品介绍页，额度均为展示示例。

本机账户、运行快照、验证截图与构建缓存不纳入仓库。
