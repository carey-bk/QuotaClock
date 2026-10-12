# Versions and updates

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` are the single source of truth for application versions. Publication is a separate step: the website points only to a verified public release in `site/config.json`.

- Stable versions use `MAJOR.MINOR.PATCH`: major for significant architecture changes, minor for features, and patch for fixes.
- Run `xcodegen generate` after editing `project.yml`. App, widget, and saver metadata reference these build settings. User-facing versions come from the bundle and use a `v` prefix; internal builds appear only in diagnostics.
- Do not override versions on the release command line. `Scripts/package-update.py` checks the built app against `project.yml` and generates `vMAJOR.MINOR.PATCH` GitHub download paths. It does not publish or alter releases.
- Sparkle appcasts retain increasing numeric builds for old clients and use three-part `shortVersionString` values. Increase both when releasing. Never rewrite old releases or tags.
- Current clients map historical appcast builds to marketing versions and compare numeric components, including `2.2.10 > 2.2.9`. A `v` prefix, legacy two-part versions, and prerelease/build suffixes are supported. Equal marketing versions do not prompt again for a different internal build; newer development versions do not downgrade.
- Entries without a parseable release version are not recommended. Arbitrary timestamps are not treated as marketing versions.
- Manual checks show a concise Chinese result. Choosing View Update opens Sparkle's release notes, download, signature verification, and installation workflow. Sparkle's installation UI follows system localization.
- Automatic checks are enabled by default, respect an explicit user opt-out, and run daily. Gentle scheduled reminders populate General settings and the menu panel's red Settings dot without a modal dialog or automatic download.
- Available-version reminders survive app restarts. Installing that version or finding no newer release clears them; a network error does not erase a known update.

## Verification

Run `swift test`, `python3 Scripts/check-updater-feed.py`, `python3 Scripts/check-update-reminders.py`, the Release Xcode build, and `python3 Scripts/check-updater-bundle.py build.noindex/Build/Products/Release/QuotaClock.app`.

Feed tests use a temporary local HTTP server and disposable applications. They do not download or install updates. See [release procedure](UPDATES.md) for signing, notarization, packaging, and public verification.
