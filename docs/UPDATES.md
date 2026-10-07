# QuotaClock update releases

QuotaClock 1.0 embeds Sparkle 2.10.0. `Scripts/prepare-sparkle.sh` downloads the
official binary distribution once and checks its pinned SHA-256 before extraction.
No Sparkle source repository clone or dependency download runs inside the app.

The app checks `https://github.com/carey-bk/QuotaClock/releases/latest/download/appcast.xml`
once per day by default. Users can disable automatic checks or request a check
from About or the app menu. Downloads require confirmation. Profile submission
and automatic downloads are disabled. Archives are Ed25519-verified before extraction.

## Signing key

The release signing key is stored only in the macOS login Keychain under Sparkle's
account `com.quotaclock.app`. Create/retrieve its public key using:

```sh
build.noindex/sparkle-tools/bin/generate_keys --account com.quotaclock.app
```

Only the public key belongs in `project.yml` / `Config/App-Info.plist`. Keep the
private key secure and backed up outside the repository. Never rotate it casually:
existing installations trust this key. Developer ID code signing is separate from
Sparkle archive signing and from Apple notarization.

## Release procedure

1. Increment both the marketing version and numeric build in `project.yml`.
2. Run `bash Scripts/prepare-sparkle.sh`, `xcodegen generate`, and `swift test`.
3. Build Release with Xcode using the release Developer ID, then run
   `python3 Scripts/sign-release.py`. This signs Sparkle helpers and all nested
   components inside-out with hardened runtime and secure timestamps, preserving
   entitlements. A normal Xcode build alone is insufficient for distribution.
4. Archive the app with `ditto -c -k --keepParent`, submit with `xcrun notarytool`
   using a Keychain profile, and require Accepted. Staple and validate the app
   and standalone saver. Verify `spctl --assess --type execute` accepts the app.
   Never put credentials in scripts or source control.
5. Package the DMG using `Scripts/package-dmg.py`, and the updater archive with
   `python3 Scripts/package-update.py --output build.noindex/release-VERSION`.
   Sign the final DMG with Developer ID and a secure timestamp, submit it for
   notarization, and staple/validate after Accepted. Generate checksums last.
6. Publish a GitHub Release containing the DMG, app-only ZIP, `appcast.xml`, and
   checksums. Every new latest release MUST include `appcast.xml` and its referenced
   ZIP; omitting them breaks the stable update URL. Never mark a prerelease latest.
7. Check the public latest appcast URL, verify the archive signature and checksum,
   and exercise Check for Updates in the installed app.

The update ZIP includes the widget and an embedded `QuotaClock.saver`. Sparkle
updates the application bundle only. About's screen saver install button opens
the embedded saver with macOS's installer so the user's chosen system/user
installation location and authorization are respected. No automatic privileged
screen saver replacement runs during app update.

0.x users must manually install 1.0 once; they do not have an updater to bootstrap.
