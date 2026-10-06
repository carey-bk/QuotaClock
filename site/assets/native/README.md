# Native QuotaClock interface assets

Captured on macOS from the unchanged QuotaClock 0.15.19 (78) production views, with an isolated preview controller and entirely fictional fixtures. No personal account screenshots or credentials are included. Alpha starts at 87%; Beta at 100%; Claude Code at 63%; DeepSeek at CNY 5.30.

- Screen saver: `Sources/Shared/AmbientDisplay.swift` and `ProviderCard.swift`.
- Widget: `WidgetCardContent` and `WidgetCardBackground` in `Sources/Shared/WidgetCardContent.swift`.
- Menu and chooser: `MenuCardsView.swift`, including `CodexAccountChooserView`.
- Menu bar status icon and percentage: `Sources/QuotaClockApp/MenuBarStatusLabel.swift`, including the native gauge drawing.
- Settings: `Sources/QuotaClockApp/SettingsView.swift`.

`Scripts/render-website-native.sh` builds an isolated app under ignored `build.noindex/`. It reads only the installed app's compiled asset catalog. `SnapshotController(onboardingPreview: true)` avoids starting the live account, credential and network services. The script exports the saver and Widget through SwiftUI ImageRenderer to ignored `Evidence/website/native/`, then opens native windows for capture. Use Command-] to advance through General, AI Services, Menu Bar, Screen Saver, Alpha menu, Beta menu, feedback menu, Alpha chooser and Beta chooser. Quit with Command-Q.

Capture settings, menus and choosers from the actual native windows using the computer-use screenshot tool. Offscreen AppKit bitmap caching omits some native controls and must not be used. For the Menu Bar and Screen Saver settings captures, hide Beta from the respective display within this isolated fixture so the preview shows Codex, Claude Code and DeepSeek. AI Services retains all four connections. Keep the original PNGs locally, and encode selected complete captures as WebP at quality 91. The feedback-menu capture is not shipped; switching success uses the real Beta menu plus an accessible website status message.

Images are not repainted or generatively edited. The website uses the app's landscape saver composition at every viewport size, including phones. The unused portrait exports remain available as source references. The web demo adds only click targets, focus indicators, a pointer animation and surrounding presentation; the native controls remain pixels from these views.

The capture window has an opaque backing, while the production menu has separate glass cards and controls. `menu-mask.svg` removes only that backing in CSS, so gaps show the website desktop. Its paths come directly from SwiftUI's continuous rounded rectangles, with the logical geometry of `MenuCardsView`, `MenuCardLayout` and `ProviderCardTokens` for the 372 × 600 capture. The same mask applies to both account states and all menu demonstrations; it does not alter the screenshot pixels. Regenerate it with `swift Scripts/export-website-menu-mask.swift > site/assets/native/menu-mask.svg` when changing the native capture layout.

The desktop corner uses a large Codex widget (360 × 360 logical points), a medium Claude Code widget (360 × 170), and a small DeepSeek widget (170 × 170). Both Codex states are exported. Run `zsh Scripts/render-website-native.sh --export-only` to export these, the status labels and the saver images without opening capture windows. Encode the status labels losslessly to preserve their small native text; the other WebP exports use quality 91. The abstract desktop wallpaper and bar surroundings are website CSS. The status label, dropdown content and all three widget bodies remain native renders.
