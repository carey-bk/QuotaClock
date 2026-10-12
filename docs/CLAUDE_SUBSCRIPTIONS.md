# Claude subscriptions and widget validation

## Current support

Claude subscription quotas can be read from Claude Code CLI or Claude Desktop, selected in AI Services. Local Token statistics cover available Code logs only. Ordinary Desktop Chat Token totals are not available through this integration. The 7-day chart ends yesterday; today's Code usage contributes to the local total immediately but enters the chart on the next day.

The following sections preserve implementation and validation history. Historical beta build numbers are not instructions to install an old package. Use the latest official release and the current build commands below.

## Research (2026-10-10)

The installed Token Monitor was Javis603/token-monitor 0.68.0. Remote research used commit `3e98bff8c0cbc1d81e9eaa86bbe9e64b53226f52`; CodexBar used `6e118bdb5782707bfb0dfd0453d3483e3b216cd0`. The installed and remote versions are not equivalent.

- [Token Monitor](https://github.com/Javis603/token-monitor#acknowledgments) credits tokscale for log parsing/Token statistics and CodexBar for AI Tool Limits research.
- [tokscale](https://github.com/junhoyeo/tokscale) is useful for local Token consumption, which cannot be directly converted to remaining subscription quotas.
- [CodexBar](https://github.com/steipete/CodexBar) is useful for multi-provider subscription integrations. Token Monitor also implements OAuth/Web/CLI quota fetching itself; it does not delegate every provider to tokscale.
- [Claude OAuth response schema](https://github.com/steipete/CodexBar/blob/6e118bdb5782707bfb0dfd0453d3483e3b216cd0/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift)
- [Claude quota mapping](https://github.com/steipete/CodexBar/blob/6e118bdb5782707bfb0dfd0453d3483e3b216cd0/Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift): `is_active` is not a reliable flag for hiding a quota window.

The native Claude parser was implemented independently from the observed protocol and behavior; this initial work introduced no Electron, tokscale, or CodexBar runtime dependency. The subsequent opt-in CodexBar engine is documented separately.

## Initial implementation

- Read the default Claude Code Keychain item, falling back to `~/.claude/.credentials.json` only when the item is absent. A denied Keychain request must not silently switch to a different file account. Credentials are never written or rotated; expired credentials require signing in again through Claude Code.
- GET `https://api.anthropic.com/api/oauth/usage` with Bearer authentication and `anthropic-beta: oauth-2025-04-20`. Use an isolated ephemeral URLSession with no shared cookies/cache or redirects. No model inference request is made.
- `utilization`/`percent` means used percentage; display `100 - used` after validating the range 0–100. Missing, Boolean, out-of-range values and invalid reset dates must not become 100% remaining.
- Support named windows, nested `rate_limits`, `limits` arrays, and legacy top-level arrays. Named Session/Weekly windows take precedence; arrays supplement model-specific weekly windows without removing unrelated models.
- Preserve each window's reset timestamp, with durations of 18,000 and 604,800 seconds for session and weekly windows. Missing reset dates remain unknown.
- Derive Plan from `subscriptionType`/`rateLimitTier` in the same credential read, never from quota values. Extra Usage reads `extra_usage`, scales minor currency units by `decimal_places` (default 2), and represents used amount / cap. Disabled and missing states are distinct. Extra Usage is not a subscription quota. Web cookie login, custom configuration directories, and multiple Claude accounts were outside this iteration.
- Reuse Codex's three card sizes. Initial Small showed Session, Weekly All, Weekly Reset, and Plan. Initial Medium added a conditional Fable Weekly field; Large used Weekly Reset, Extra Usage, optional Limit Resets, and Fable progress. Later layout changes are recorded below. Other model windows remain in the data layer. A missing Session is never replaced with a weekly quota mislabeled as Session. Other providers retain their generic templates.
- Keep stale status in the menu footer rather than adding card rows that would overflow the layout.

## Fixtures and validation limits

`Tests/Fixtures/Claude/usage-fable.json` is a **synthetic protocol fixture**, not a real local account response. `Scripts/render-subscriptions.sh` uses the actual parser and shared views for English/Chinese normal, exhausted, 100%, expired, signed-out, single-window, missing-reset, multi-model, and Kimi examples in three sizes. The initial run rendered 60 cards on 20 sheets. It does not access Keychain, the network, or production snapshots. Kimi fixtures demonstrate layout, not verified connectivity.

The initial iteration passed 181 Core tests and a Release build. Local CoreSimulator/plugin version warnings did not prevent the macOS build. Real-account OAuth permissions, official quota/reset agreement, WidgetKit refresh, offline states, and Keychain authorization still needed separate verification. Static renders are not live WidgetKit acceptance.

Kimi/GLM/Bailian reused existing adapters and layouts. This did not revalidate their live APIs; each requires sanitized protocol samples and real-account comparisons.

## Historical version state

The initial source was 1.2.0-beta.8 (91), with beta.7 (90) installed. The earlier beta.1 (84) package did not include those layout changes. These are historical observations, not the current release state.

## Real-account testing

1. Download the latest release for Intel or Apple Silicon, requiring macOS 14+. Quit the old application before replacing it in Applications; do not run two copies.
2. Use a Claude subscription with either Claude Code or Desktop. Select the matching login source in AI Services; installing the other client is unnecessary.
3. Connect Claude Subscription, enable the desired surfaces, and refresh. The account owner decides whether to approve any macOS Keychain prompt.
4. Compare with the official usage page or Claude Code `/usage`. Record the comparison time, session and all-model weekly usage, model-specific weekly usage, and each reset date. QuotaClock displays **remaining**: 28% used becomes 72% remaining. Rounding can cause a one-point difference.
5. Confirm the main value is the session window. If absent, Session stays unknown and Weekly All retains the weekly value. Check model names and reset dates in the local time zone.
6. Inspect all three widget sizes and the menu panel. Offline refresh must preserve the last successful values and display stale/error status in the footer without shifting card contents. Reconnection should recover on refresh.
7. Renew expired login in the selected Claude client before retrying. Record the time and UI state for 403, rate-limit, or network failures; avoid repeated rapid refreshes.
8. Share only macOS/QuotaClock versions, Desktop or CLI source, plan, redacted screenshots, comparison time/time zone, and discrepancy. **Never share access tokens, refresh tokens, cookies, Keychain exports, or raw credential files.**

## Reproduction

```sh
swift test
xcodebuild -project QuotaClock.xcodeproj -scheme QuotaClock -configuration Release \
  -derivedDataPath build.noindex build
zsh Scripts/render-subscriptions.sh
```

Local research captures and test logs are stored under `Evidence/claude-research-20261010/` and are not published as account data.

## Subsequent visual refinements (2026-10-10)

Small remained unchanged; Medium retained a text-only Fable percentage. Large initially used Weekly Reset / Extra Usage on the left and Fable Weekly progress / Fable Reset on the right. Weekly All omitted the redundant Remaining suffix. Session kept its main number and Session Remaining label. Extra Usage stayed a currency value without a progress bar to avoid conflating spending and remaining quota. Parsing and plan detection were unchanged.

A follow-up put Fable Reset above Fable Weekly. Codex Large was also adjusted to show Weekly Limit even when the weekly window is the only/main window, using the same compact main/statistics heights as Plus. `zsh Scripts/render-codex-large.sh` covers Plus, weekly-only, and 0% fixtures in English and Chinese.

## Latest Large layout (build 91 source; installed build 90)

Left: WEEKLY RESET / EXTRA USAGE. Right: optional LIMIT RESETS / FABLE WEEKLY percentage and horizontal progress bar. FABLE RESET is removed from this card.

Read-only reset inventory uses cedar_ember.grants: sum integer resets_left for started, unexpired, unpaused grants. usable_now=false does not mean empty inventory. Missing, ineligible or malformed inventory is hidden; an explicit empty inventory displays 0. Query cedar_ember=1 falls back to ordinary usage on HTTP 400/403. No CLI User-Agent impersonation or reset mutation. Fable and reset inventory are independently optional.

The sample count 2 is synthetic, not verified against a real Claude account. Preview coverage now includes missing reset inventory and totals 20 bilingual sheets / 60 cards. Prior version and testing instructions above are historical; do not use build 84 to validate this layout.


### Large token-history chart

Large now uses three bottom columns: Weekly Reset / Extra Usage, optional Limit Resets / Fable Weekly, and 7D TOKENS. The chart reuses the Codex renderer (daily bars, maximum and date labels), reading usage.dailyHistory only. Claude OAuth usage does not currently populate that history in this adapter: production therefore displays No history until a real token-history source is connected. Preview history is synthetic and never published to account snapshots. Updated preview coverage: 22 bilingual sheets / 66 cards, including a no-history case. Small and Medium layouts are unchanged.


### Pro / Max layout revision (build 94 source)

The latest layout supersedes the earlier Large Extra Usage arrangement. Small stays Session / Weekly All / Weekly Reset / Plan. Medium shows Plan and optional Limit Resets; Pro shows optional Fable Weekly as the third field, while Max shows Last Day. Large shows Limit Resets / Peak Day for Pro, Limit Resets / optional Fable Weekly plus a bar for Max, Total Tokens / Last Day in the second column, and the shared 7D TOKENS chart on the right. Only the main-metric divider and the divider between the two statistics columns remain. There are no added horizontal section separators or divider beside the chart.

Max is selected only from credential-derived plan names Max or Max followed by a tier (5x / 20x); counts and Fable availability are never inferred from the plan. Unknown token values show an em dash and missing history shows No history. Token figures in previews remain synthetic; no new production token collector was added. Coverage: 26 bilingual sheets / 78 cards, including Pro, Max 5x, Max 20x and missing optional data. Installed version remains build 93 until a subsequent installation.

## Desktop support (1.2.1)

Reads Desktop oauth:tokenCacheV2 through Claude Safe Storage / Claude Key. Only the active account, official API host and unique unexpired user:profile entry are eligible. No token refresh or Desktop writes; no CLI fallback on Desktop auth failure. Switching sources invalidates old quota. Existing users keep CLI as default. macOS V2 cache verified locally with Pro: HTTP 200, Session 94% and Weekly 99% remaining at test time. No Desktop token history integration.

## Local token statistics (1.2.2)

Implemented `ClaudeLocalUsage` against CodexBar's pinned `CostUsageScanner+Claude.swift` and `ClaudeDesktopProjectsLocator.swift`. Counts input + output + cache creation + cache read tokens. Uses final cumulative message/request chunks, preferring complete parent copies over incomplete proxy estimates and subagent copies. No pricing or estimated token conversion.

- Desktop: embedded `.claude/projects` roots within Desktop Code/Cowork session directories (discovery capped at depth 4), plus shared Code sessions explicitly linked by Desktop `cliSessionId` metadata.
- CLI / Other: remaining `~/.claude/projects` and `~/.config/claude/projects` records. Unmarked Desktop sessions cannot reliably be separated from CLI; label does not claim CLI-only. No backups or custom profiles are silently merged.
- These are surviving machine-local logs, potentially spanning account switches. They are not current-account subscription totals. Ordinary Desktop conversations are excluded. The selected login source selects the statistics scope.
- LOCAL TOKENS: all available selected local records through now. PEAK DAY: maximum local calendar-day sum. LAST DAY: yesterday. Chart: seven completed local calendar days through yesterday; missing dates within a readable dataset have zero recorded tokens. No records means unavailable, never a fabricated zero.
- No chat text, paths, session identifiers or credentials enter snapshots; only numeric aggregates, dates and an allowlisted scope/status enum. File parsing is bounded, ignores symlinks, caches unchanged files by size/mtime and memoizes scans for 60 seconds. Incomplete/failed/over-budget scans hide totals rather than report partial sums.
- Runtime bounds: 20,000 discovered entries, 32 MB/file, 2 MB/line, 256 MB changed log bytes per scan, 200,000 rows, 8-second discovery/read budget. Larger histories report unavailable; they are not silently truncated into a false total.
- Local verification on 2026-10-12 found no CLI or Desktop Code JSONL usage records. The real scanner returns noRecords for both scopes; ordinary chat/plan-percentage history is not substituted. Fixture tests cover actual JSONL protocol, aggregation, source mapping and chart projection.
