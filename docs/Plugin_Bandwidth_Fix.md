# Quota polling plugin bandwidth fix — 0.15.20 (79)

QuotaClock starts a short-lived Codex app-server for account reads. Codex CLI
0.160.0 enables plugins by default and initiates curated repository synchronization
on startup. Account sessions use disposable homes: successful linked reads delete
the directory, and independent reads delete it after credential reconciliation.
Therefore even a completed plugin download cannot provide a persistent cache.
Stopping a running sync can additionally leave unfinished downloads.

Both `IsolatedCodexRPC` (login and account reads) and the legacy
`CodexAppServerTransport` now use a common argument builder that passes
`-c features.plugins=false`. This override applies only to the child process.
The user's global Codex configuration, account isolation, credential recovery,
and refresh interval remain unchanged.

Configuration override syntax reference:
https://learn.chatgpt.com/docs/config-file/config-basic
The installed CLI's `features list` also identifies `plugins` as a stable feature.

## Validation on 2026-10-06

- New subprocess regression: failed before the fix; passed after it. It exercises
  browser-login fixtures and repeated reads for linked and independent accounts.
- `swift test`: 164 tests passed.
- Installed CLI startup comparison, fresh unauthenticated homes, 15 seconds each:
  baseline invoked Git for `https://github.com/openai/plugins.git` and created
  `.tmp/plugins.sync.lock`; fixed invocation made no Git calls and created no
  plugin files. Initialization and `account/read` succeeded in both cases.
  Git HTTP traffic was directed to a closed loopback proxy to avoid downloading
  the repository during reproduction. This is a startup-trigger check, not a
  measurement of total VPN bytes.
- Real isolated `account/rateLimits/read` passed using the existing isolation
  smoke helper. A quota meter was parsed and matched the current account;
  active auth bytes and modification time were unchanged, with no Keychain
  writes or saved refresh-token copies.
- Release app build succeeded. Xcode emitted unrelated device/simulator plugin
  compatibility warnings; macOS targets compiled successfully.

Repeat the startup comparison after Codex updates:

```sh
python3 Scripts/check-codex-plugin-startup.py \
  /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex
```

Local logs are in ignored `Evidence/plugins-*` files.

## Installed acceptance

At the user's request, installed 0.15.20 (79) to `/Applications/QuotaClock.app`
and `/Library/Screen Savers/QuotaClock.saver`. Old bundles were moved to
recoverable backup locations; account and preference stores were preserved.
PluginKit lists only the installed 0.15.20 widget extension, and the running
app's About pane visibly reports 0.15.20 / 79. Removed one 24,467,064-byte
unfinished plugin clone from the account session into the installation backup.
One saved account requires login; this was already visible on initial startup.
Ordinary quota requests still require network access.


Traffic follow-up: the installed-app observation was not suitable for estimating
normal polling costs because Codex products were in unavailable/authentication
backoff. Do not interpret the low/zero sampled bytes as zero daily usage.
A separate successful live isolated account read using the same fixed core
recorded 36,112 bytes received + 11,831 bytes sent (47,943 bytes total) in nettop.
At 1,440 reads/day this is about 69 MB per account per day, or about 207 MB for
three accounts. This is a short-sample extrapolation, not a VPN billing guarantee;
sampling, TLS/proxy overhead, retries, other providers and response changes apply.
Evidence: `Evidence/plugins-single-read-traffic.json`.
