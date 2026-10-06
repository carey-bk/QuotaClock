# QuotaClock website: asset and architecture audit

Audit completed 2026-10-06, before Phase 1 implementation.

## Existing project

- Swift/Xcode application; no website, .git directory, Git remote or GitHub Actions in this directory.
- Read-only GitHub repository listing for the known account returned no QuotaClock repository. Repository and release destinations requested from the owner; never assume that an unpublished local version is a public release.
- `project.yml`: version 0.15.19, build 78, macOS deployment target 14.0. The README version is older and is not used for current metadata.
- CPU distribution support has not been confirmed from a Release binary. Keep architecture claims absent until verified.

## Reuse inventory

| Asset | Source | Decision |
| --- | --- | --- |
| MacBook front hardware | LiveCopilot `site/assets/ls-front-hardware.webp` and `.png` | Copy the existing exports and provenance note; no PSD or new third-party mockup |
| Screen placement | LiveCopilot `site/phase5.css` | Preserve image aspect 4610/2669; left 10.673%, top 2.136%, width 78.633%, height 86.587%; notch clipping |
| App icon | `Assets/QuotaClock.xcassets/AppIconSilver.appiconset` | Reuse silver icon and small icon |
| Provider marks | `Assets/QuotaClock.xcassets/Provider*.imageset` | Reuse six SVG marks, preserve Lobe Icons MIT notice |
| Screen saver UI | `Sources/Shared/AmbientDisplay.swift`, `ProviderCard.swift`, `AmbientBackdrop.swift` | HTML/CSS reconstruction; black canvas, dark beveled cards, serif metrics, italic account names |
| Settings / menu screenshots | `Evidence/phase4_2`, `Evidence/phase4_3`, earlier UI evidence | Reference only, do not copy personal account screenshots into the public site |
| Colors | `SettingsDesign.swift`, `ProviderCard.swift` | Champagne accent #b39257; dark cards, warm light text |
| Fonts | System font + browser serif fallback | No Apple font files copied or distributed |

## Verified product capabilities

`ProviderCatalog` in `Sources/QuotaCore/ProductModels.swift` and registration in `Sources/QuotaClockApp/QuotaClockApp.swift` are authoritative:

- Codex subscriptions; Claude Code subscriptions; DeepSeek API balance.
- GLM Coding Plan; Kimi Code and Kimi Open Platform (China and International).
- Qwen / Bailian Coding Plan and Token Plan via the official CLI.
- GLM Standard API, Kimi Extra Usage and Bailian Pay-as-you-go are explicitly unsupported. Do not claim all products of a provider are supported or promise a release date.
- Codex manual account switch exists in `AccountsController.swift`, `CodexAccountStore.swift` and `CodexDesktopSwitch.swift`. No automatic switch / load balancing claim.
- Demonstrations use only Alpha, Beta, Gamma, Delta. Data is illustrative and no login is accessed by the website.

## Architecture decision

Use `site/` for HTML partials, CSS, JS, public assets and deployment configuration. `Scripts/build-site.py` reads app version/minimum macOS and produces `_site/`. No frontend dependencies or WebGL. GitHub Pages workflow uploads only `_site/`; GitHub publication requires the owner's actual repository. Relative asset paths support both project subpaths and custom-domain roots. Production builds must reject missing repository/release configuration.

Design: centered headline and device, followed by a larger unframed screen saver. Unequal surface composition; independent switch section. Warm white #f6f5f1, graphite #20211f, silver #caccC4, champagne #b39257. Preserve the product's serif data language without turning the site into a serif editorial template.

## Ordered delivery

1. Foundation and asset integration → Desktop/Mobile gate.
2. Hero and Screen Saver → Desktop/Mobile gate.
3. Product Surfaces → Desktop/Mobile gate.
4. Codex Switching → Desktop/Mobile gate.
5. Settings, Providers and remaining content → Desktop/Mobile gate.
6. Polish, accessibility, performance, metadata, 404 and production verification.

Per-stage evidence: `Evidence/website/VALIDATION.md`.

## Repository handoff and release verification

After the initial audit, the owner published `carey-bk/QuotaClock` and requested replacing its simple GitHub Pages page. The initial public commit is `56ef903`. Pages uses the existing Actions deployment; the workflow now builds and validates `_site/` instead of publishing `site/dist/` directly.

GitHub Release `v0.15.19` includes `QuotaClock-0.15.19-78.dmg` (32,734,391 bytes). The installed build reports 0.15.19 (78), macOS 14.0, and a universal arm64 / x86_64 executable. These checks enable the public download and architecture labels. The release describes Developer ID signing without completed notarization, Codex restart during account switching, and macOS-controlled Widget refresh; the website preserves those details.
