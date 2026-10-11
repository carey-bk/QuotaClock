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

当前正式版本 **1.1.0 (81)**，安装包包含 Apple Silicon 与 Intel 架构；应用与 DMG 均使用 Developer ID 签名并通过 Apple 公证。源码部署目标为 macOS 14+，各系统展示能力与表现可能不同。

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

版本与发布规范：[版本管理](docs/VERSIONING.md)。原始 Logo 位于 `Assets/Originals/`。

- `Sources/QuotaCore`：数据模型、接入与快照逻辑。
- `Sources/QuotaClockApp`：macOS 设置与菜单栏应用。
- `Sources/QuotaWidget`、`Sources/QuotaSaver`：系统展示扩展。
- `site/dist`：无构建依赖的产品介绍页，额度均为展示示例。

本机账户、运行快照、验证截图与构建缓存不纳入仓库。


### 扩展数据接入（CodexBar 引擎）

新增固定版本的 CodexBar Core / CLI 数据引擎，提供 100 个上游接入 ID，涵盖模型商、编程工具和聚合平台。保留原有 6 家服务商的 9 个原生适配器；同一公司的多个产品入口不计为多家模型商。新增入口默认关闭，可在「AI 服务 → 添加服务商 → CodexBar」中选择。

这些入口已纳入源码和统一采集流程，不代表 100 个真实账号均已验证。各入口需要对应登录或凭证；浏览器读取需单独开启。原生 Codex 多账号、Claude 布局及账号数据保持独立。详细能力边界、数据映射、构建步骤和完整目录见 [数据引擎接入说明](docs/integrations/CODEXBAR_ENGINE.md)。

首次构建主应用前运行 `zsh Scripts/build-provider-engine.sh`；此步骤只在构建时下载依赖，运行时不会下载或克隆引擎。
