# QuotaClock

**Your AI limits, at a glance.** A native macOS app for monitoring AI subscription limits and API balances in the menu bar, desktop widgets, and a screen saver.

**English** · [简体中文](docs/README.zh-Hans.md) · [繁體中文](docs/README.zh-Hant.md)

[Website](https://carey-bk.github.io/QuotaClock/) · [Download](https://github.com/carey-bk/QuotaClock/releases/latest) · [Documentation](docs/README.md)

## Features

- **Three native surfaces:** a configurable menu bar panel, WidgetKit widgets, and a `.saver` screen saver.
- **Multiple accounts and services:** native Codex accounts, Claude subscriptions, supported local CLI tools, and API balances.
- **Extended integrations:** a pinned CodexBar Core/CLI engine provides 100 upstream integration IDs across providers, coding tools, and aggregators. Entries are opt-in and require their own credentials; inclusion is not a claim that every service has been tested with a real account.
- **Claude Desktop and CLI:** read subscription quotas from the selected login source. Local Token totals and daily charts cover available **Code logs**, with Desktop-linked logs separated from CLI / other logs. Ordinary Desktop Chat Token accounting is not supported.
- **Personalization:** light, dark, and system appearance; two app icons; provider or gauge menu bar icons; per-surface visibility and ordering.
- **Auto Hero:** prioritize the currently signed-in account for the selected Hero provider, or keep a custom order.
- **Codex account switching:** save the current login, switch credentials, and reopen Codex. Finish active work before switching because it interrupts running tasks.
- **Quiet update discovery:** automatic daily checks are enabled by default. Available updates appear on the General settings page and as a red dot on the menu panel's Settings button. Downloads require confirmation.

## Install

1. Download the latest DMG from Releases and drag QuotaClock to Applications.
2. Open the app and follow the setup guide to connect services.
3. Add desktop widgets with macOS **Edit Widgets**.
4. To use the screen saver, double-click `QuotaClock.saver`, then select it in System Settings. Installing it does not automatically make it the active screen saver.

Requires **macOS 14 or later**. Release packages support **Apple Silicon and Intel**. Official app and DMG releases are Developer ID signed and Apple notarized. See [Releases](https://github.com/carey-bk/QuotaClock/releases/latest) for the current published version.

## Updates

Use **General → Software Updates**, **About**, or the app menu to check manually. Automatic checks run independently of quota polling and can be disabled. Background checks do not open modal dialogs or start downloads.

App updates include the widget. Update an installed standalone screen saver separately through **About → Install or Update Screen Saver**; macOS may request administrator authentication. Versions before 1.0 need a one-time manual upgrade.

## Build and test

Install Xcode, the Swift toolchain, and XcodeGen. Before the first application build, prepare the pinned dependencies:

```sh
bash Scripts/prepare-sparkle.sh
zsh Scripts/build-provider-engine.sh
xcodegen generate
swift test
xcodebuild -project QuotaClock.xcodeproj -scheme QuotaClock \
  -configuration Debug -derivedDataPath build.noindex build
```

Distribution requires your own Apple Developer team, certificates, App Group, and entitlements. The repository's team identifier belongs to the original author's builds; no private signing keys are included. QuotaCore tests do not require distribution certificates. Dependencies are prepared at build time; the app does not clone or download the provider engine at runtime.

## Data and limitations

The main app fetches data and publishes local snapshots for the menu bar, widgets, and screen saver. Saved independent credentials use macOS Keychain; linked sessions read the selected local login. Missing or stale data is labeled rather than replaced with invented quotas. WidgetKit controls widget refresh timing.

Claude quotas describe the subscription; local Token figures describe surviving logs on this Mac, potentially spanning account switches. Token charts show seven completed local calendar days through yesterday. Missing logs are unavailable, not zero. See [Claude integration](docs/CLAUDE_SUBSCRIPTIONS.md) for the exact scope.

QuotaClock is not an official product of OpenAI, Anthropic, or any other provider. Third-party attribution is in `Assets/LobeIcons-LICENSE`, `Assets/Fonts`, and `Vendor/CodexBar/LICENSE`. This repository does not currently grant an overall open-source license.

## Repository layout

- `Sources/QuotaCore`: models, integrations, and snapshot logic.
- `Sources/QuotaClockApp`: settings and menu bar application.
- `Sources/QuotaWidget`, `Sources/QuotaSaver`: native display extensions.
- `site`: English-first website with Simplified and Traditional Chinese switches. Demo accounts and values are illustrative.
- `docs`: English technical documentation; translated introductions are linked above.

Local accounts, runtime snapshots, verification captures, and build caches are not published. Original artwork is preserved in `Assets/Originals`.
