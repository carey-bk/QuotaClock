# Native QuotaClock interface assets

Captured on macOS from the unchanged QuotaClock 0.15.19 (78) production views, with an isolated preview controller and entirely fictional fixtures. No personal account screenshots or credentials are included. Alpha starts at 87%; Beta at 100%; Claude Code at 63%; DeepSeek at CNY 5.30.

- Screen saver: `Sources/Shared/AmbientDisplay.swift` and `ProviderCard.swift`.
- Widget: `WidgetCardContent` and `WidgetCardBackground` in `Sources/Shared/WidgetCardContent.swift`.
- Menu and chooser: `MenuCardsView.swift`, including `CodexAccountChooserView`.
- Settings: `Sources/QuotaClockApp/SettingsView.swift`.

`Scripts/render-website-native.sh` builds an isolated app under ignored `build.noindex/`. It reads only the installed app's compiled asset catalog. `SnapshotController(onboardingPreview: true)` avoids starting the live account, credential and network services. The script exports the saver and Widget through SwiftUI ImageRenderer to ignored `Evidence/website/native/`, then opens native windows for capture. Use Command-] to advance through General, AI Services, Menu Bar, Screen Saver, Alpha menu, Beta menu, feedback menu, Alpha chooser and Beta chooser. Quit with Command-Q.

Capture settings, menus and choosers from the actual native windows using the computer-use screenshot tool. Offscreen AppKit bitmap caching omits some native controls and must not be used. For the Menu Bar and Screen Saver settings captures, hide Beta from the respective display within this isolated fixture so the preview shows Codex, Claude Code and DeepSeek. AI Services retains all four connections. Keep the original PNGs locally, and encode selected complete captures as WebP at quality 91. The feedback-menu capture is not shipped; switching success uses the real Beta menu plus an accessible website status message.

Images are not repainted or generatively edited. Portrait saver composition is the app's own Hero-plus-one-secondary layout. The web demo adds only click targets, focus indicators, a pointer animation and surrounding presentation; the native controls remain pixels from these views.
