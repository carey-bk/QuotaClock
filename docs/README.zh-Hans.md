# QuotaClock

[English](../README.md) · **简体中文** · [繁體中文](README.zh-Hant.md)

**AI 额度，一眼掌握。** 在 macOS 菜单栏、桌面小组件和屏幕保护程序中查看 AI 服务的剩余额度与余额。

[官网](https://carey-bk.github.io/QuotaClock/) · [下载最新版](https://github.com/carey-bk/QuotaClock/releases/latest) · [技术文档（英文）](README.md)

## 主要功能

- 支持 Codex 多账户、Claude 订阅及受支持的 CLI/API 服务。
- 集成固定版本的 CodexBar 引擎，提供 100 个可选接入 ID。这不代表 100 家服务都经过真实账号验证；每个入口需要对应的登录或凭据。
- Claude 可选择 Desktop 或 Code CLI 登录来源读取订阅额度。Token 统计只读取本机可用的 **Code 日志**，区分 Desktop 关联日志与 CLI／其他日志，**不包含普通 Desktop Chat**。
- 三种尺寸的小组件、菜单栏面板与屏保；支持主题、图标、排序、逐入口显示控制与 Auto Hero。
- 可保存和切换 Codex 账户。切换会中断正在运行的任务，请先完成当前工作。
- 默认每天自动检查更新；发现更新后在设置首页显示，并在菜单栏面板的设置按钮上显示红点。后台检查不弹窗，确认后才下载。

## 安装与更新

需要 macOS 14 或更新版本，支持 Apple Silicon 与 Intel。正式发布包使用 Developer ID 签名并通过 Apple 公证。

1. 下载 DMG，将 QuotaClock 拖入 Applications，然后完成应用内引导。
2. 通过 macOS「编辑小组件」添加桌面小组件。
3. 需要屏保时双击 `QuotaClock.saver` 安装，再到系统设置中选用。
4. 在「通用 → 软件更新」、关于页或应用菜单手动检查更新；自动检查可以关闭。

应用更新包含小组件；独立屏保需要通过「关于 → 安装或更新屏幕保护程序」另行更新。0.x 版本需要先手动升级一次。

## 数据范围

主应用采集数据，其他展示入口读取本地快照。独立登录凭据保存在 macOS 钥匙串中。缺失或过期数据会明确标识，不会生成虚假额度。桌面小组件刷新时机由 macOS 决定。

Claude 本地 Token 总量可能包含本机历史切换过的账户，并非当前订阅的完整用量。7 天柱状图统计截至昨天的 7 个完整本地自然日；当天的 Code 用量会先计入总量。没有日志时显示不可用，不当作零。

QuotaClock 不是 OpenAI、Anthropic 或其他服务商的官方产品。仓库目前未授予项目整体的开源许可证。构建、第三方许可与接入细节请查阅[英文文档](README.md)。
