# Claude 订阅接入与小组件测试（2026-10-10）

## 研究结论

本机 Token Monitor 为 Javis603/token-monitor 0.68.0。研究时远端代码固定为
`3e98bff8c0cbc1d81e9eaa86bbe9e64b53226f52`；CodexBar 固定为
`6e118bdb5782707bfb0dfd0453d3483e3b216cd0`。本机版本不等于该远端版本。

- [Token Monitor README](https://github.com/Javis603/token-monitor#acknowledgments) 明确致谢 tokscale 的日志解析/Token 统计，以及 CodexBar 的 AI Tool Limits 研究。
- [tokscale](https://github.com/junhoyeo/tokscale) 适合研究本地 Token 消耗；它不能把本机 Token 数直接换算成订阅剩余额度。
- [CodexBar](https://github.com/steipete/CodexBar) 更适合研究多家订阅额度接入。Token Monitor 同样有自己的 OAuth/Web/CLI 额度实现，不是所有供应商都交给 tokscale。
- [Claude OAuth 响应定义](https://github.com/steipete/CodexBar/blob/6e118bdb5782707bfb0dfd0453d3483e3b216cd0/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift)
- [Claude 额度映射](https://github.com/steipete/CodexBar/blob/6e118bdb5782707bfb0dfd0453d3483e3b216cd0/Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift)：特别注意 `is_active` 不是可直接用于隐藏额度的生效标记。

这里只参考接口字段及行为，独立实现 QuotaClock 解析，没有引入 Electron、tokscale 或 CodexBar 的运行时依赖。

## 本轮实现

- 主程序只读 Claude Code 默认登录的 Keychain 项；不存在时读取 `~/.claude/.credentials.json`。拒绝 Keychain 授权时不绕过为另一份文件账号；不写入或轮换 Claude 凭证。过期凭证要求回到 Claude Code 更新登录。
- GET `https://api.anthropic.com/api/oauth/usage`，Bearer 和 `anthropic-beta: oauth-2025-04-20`。独立临时 URLSession，不用共享 Cookie/缓存，不跟随重定向。无模型推理请求。
- `utilization`/`percent` 为已用比例，显示 `100 - used`，数值验证范围 0–100。缺失、布尔、越界、非法重置日期不能变成 100% 可用。
- 同时支持具名窗口、嵌套 `rate_limits`、`limits` 数组和旧的顶层数组。具名 Session/Weekly 优先；数组提供补充模型周窗口；只替换同一模型的旧字段，不抹掉其他模型。
- 每个窗口保留自己的重置时间。5 小时与周窗口分别记录 18000/604800 秒。没有重置时间显示未知，不伪造时间。
- Plan 取自同一次读取的 Claude Code 凭证元数据 subscriptionType/rateLimitTier，不由额度推测。Extra Usage 读取 extra_usage，按 decimal_places（缺省2）换算最小货币单位；展示已用金额/上限，关闭显示 Disabled，缺失显示 —，不视为套餐内额度。Web Cookie 登录、自定义配置目录及多个 Claude 账号不在本轮范围。
- Claude 三种尺寸复用 Codex 布局。Small：Session 主数、Weekly All 进度、Weekly Reset、Plan；Medium：右侧 Plan、Weekly Reset、仅在存在套餐内 Fable 窗口时显示 Fable Weekly；Large：底部 Weekly Reset、Extra Usage，以及条件显示的 Limit Resets、Fable Weekly 和进度。其他模型窗口仍保留在数据层，但不占默认卡片。无 Session 时不把 Weekly 误标成 Session。国模仍使用上一版通用模板。
- 卡片不新增 Stale 状态行，避免撑高；刷新状态继续由菜单底部显示。

## 示例数据与验证边界

`Tests/Fixtures/Claude/usage-fable.json` 为**人工构造**的协议样例，绝非本机真实 Claude 账号返回。
`Scripts/render-subscriptions.sh` 使用真实解析器和共享卡片 View，生成中英文、三种尺寸的正常/耗尽/100%/过期/无账号/单窗口无重置/多模型和 Kimi 模板，共 60 张卡片（20 张对照图）。预览脚本不访问 Keychain、不联网、不写主程序快照。Kimi 预览同样是合成布局数据，不证明其接入正确。

本轮 Core 测试 181 项通过；Release 构建通过（Xcode 报告了本机 CoreSimulator/插件版本不匹配警告，macOS 目标仍构建成功）。还需真实账号验证：OAuth 权限是否满足、官方百分比/重置时间是否一致、真实 WidgetKit 桌面刷新、断网后的状态以及 Keychain 授权体验。静态图片不是 WidgetKit 实机验收。

国模沿用现有 Kimi/GLM/Bailian 产品适配器，本轮只复用布局；没有宣称重新验证它们的线上接口。后续逐家提供脱敏协议样例和真实账号对照后才能确认准确。

## 版本状态

当前源码构建为 1.2.0-beta.8 (91)，包含最新 Claude Large 布局。本机已安装版本为 beta.7 (90)。此前发出的 beta.1 (84) 测试包不包含这次布局，请勿用它验收这次修改。当前轮未重新打包/安装。

## 同学测试步骤

1. 测试包版本为 `1.2.0-beta.1 (84)`，支持 Intel / Apple Silicon Mac，最低 macOS 14。退出旧版 QuotaClock，将包中的 App 拖到“应用程序”后打开。不要同时运行两个版本。
2. 需要 Claude **订阅账号**及已登录的 **Claude Code 默认配置**。如果只有 Claude Desktop，先确认是否愿意安装/登录 Claude Code；无需向开发者提供账号或凭证。
3. 在 QuotaClock 设置 → AI Services 中连接 Claude Code Subscription，启用菜单栏/小组件显示，手动刷新。首次系统 Keychain 提示由本人选择是否授权。
4. 同时打开该账号官方用量页面或 Claude Code `/usage`。记录对照时间、当前窗口已用比例、全模型周已用比例、模型专属周已用比例，以及每项重置时间。QuotaClock 显示**剩余**，例如官方已用 28% 对应这里 72%；小数可能因官方取整相差 1 个百分点。
5. 确认主数对应 5 小时；如果该窗口不存在，则 Session 显示未知，周额度保留在 Weekly All 进度条，不生成虚假的 100%。核对每项模型名称与各自重置时间，所有时间按本机时区展示。
6. 添加小/中/大桌面小组件检查布局；菜单展开时对照数据。断网后手动刷新：保留上次成功值，菜单底部显示过期/失败状态，卡片不能下移挤出边界。恢复网络再刷新应恢复。
7. 若提示登录失效，先在 Claude Code 更新登录，再刷新。遇到 403、限流或网络错误记录发生时间及界面状态，不反复快速刷新。
8. 反馈只需：macOS 版本、QuotaClock 版本、使用的是 Claude Code 还是 Desktop、订阅类型、脱敏截图、核对时间/时区、误差。**不要发送 accessToken、refreshToken、Cookie、Keychain 导出或原始凭证文件。**

## 复现命令

```sh
swift test
xcodebuild -project QuotaClock.xcodeproj -scheme QuotaClock -configuration Release \
  -derivedDataPath build.noindex CURRENT_PROJECT_VERSION=84 MARKETING_VERSION=1.2.0-beta.1 build
zsh Scripts/render-subscriptions.sh
```

测试日志/研究摘录/成图保存在本机 `Evidence/claude-research-20261010/`，未提交为公开账号数据。

## 2026-10-10 后续视觉调整

依据《Claude小组件映射逻辑》最新讨论：Small 保持；Medium 保留纯文字 Fable 百分比；Large 底部改为两列，左列 Weekly Reset / Extra Usage，右列 Fable Weekly 横向进度 / Fable Reset。Weekly All 只显示百分比，省略重复 Remaining。Session 保留主数字和 Session Remaining 标签；Extra Usage 仍为金额，不增加进度条，避免混淆已用金额与剩余百分比。此次不改变额度解析或套餐判定。

后续微调：Large 右列顺序改为 Fable Reset 在上、Fable Weekly 横条在下。Codex 大卡直接识别周窗口，即使周窗口本身是唯一/主窗口，也显示中部 Weekly Limit 进度条，并使用与 Plus 一致的紧凑主数字/统计区域高度。验证脚本：`zsh Scripts/render-codex-large.sh`（Plus、周窗口单独存在、0% 三组中英文示例）。


## Latest Large layout (build 91 source; installed build 90)

Left: WEEKLY RESET / EXTRA USAGE. Right: optional LIMIT RESETS / FABLE WEEKLY percentage and horizontal progress bar. FABLE RESET is removed from this card.

Read-only reset inventory uses cedar_ember.grants: sum integer resets_left for started, unexpired, unpaused grants. usable_now=false does not mean empty inventory. Missing, ineligible or malformed inventory is hidden; an explicit empty inventory displays 0. Query cedar_ember=1 falls back to ordinary usage on HTTP 400/403. No CLI User-Agent impersonation or reset mutation. Fable and reset inventory are independently optional.

The sample count 2 is synthetic, not verified against a real Claude account. Preview coverage now includes missing reset inventory and totals 20 bilingual sheets / 60 cards. Prior version and testing instructions above are historical; do not use build 84 to validate this layout.


### Large token-history chart

Large now uses three bottom columns: Weekly Reset / Extra Usage, optional Limit Resets / Fable Weekly, and 7D TOKENS. The chart reuses the Codex renderer (daily bars, maximum and date labels), reading usage.dailyHistory only. Claude OAuth usage does not currently populate that history in this adapter: production therefore displays No history until a real token-history source is connected. Preview history is synthetic and never published to account snapshots. Updated preview coverage: 22 bilingual sheets / 66 cards, including a no-history case. Small and Medium layouts are unchanged.


### Pro / Max layout revision (build 94 source)

The latest layout supersedes the earlier Large Extra Usage arrangement. Small stays Session / Weekly All / Weekly Reset / Plan. Medium shows Plan and optional Limit Resets; Pro shows optional Fable Weekly as the third field, while Max shows Last Day. Large shows Limit Resets / Peak Day for Pro, Limit Resets / optional Fable Weekly plus a bar for Max, Total Tokens / Last Day in the second column, and the shared 7D TOKENS chart on the right. Only the main-metric divider and the divider between the two statistics columns remain. There are no added horizontal section separators or divider beside the chart.

Max is selected only from credential-derived plan names Max or Max followed by a tier (5x / 20x); counts and Fable availability are never inferred from the plan. Unknown token values show an em dash and missing history shows No history. Token figures in previews remain synthetic; no new production token collector was added. Coverage: 26 bilingual sheets / 78 cards, including Pro, Max 5x, Max 20x and missing optional data. Installed version remains build 93 until a subsequent installation.
