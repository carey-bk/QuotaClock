#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p Evidence
python3 Scripts/generate-localizations.py
# The checked-in .xcodeproj works without XcodeGen. Regenerate only after project.yml edits.
/usr/bin/xcodebuild -project QuotaClock.xcodeproj -scheme QuotaClock -configuration Debug -derivedDataPath build.noindex build | tee Evidence/build.log
# Xcode registers its build product with Launch Services. Keep the installed copy
# as the only discoverable QuotaClock app/Widget after local builds.
product="$PWD/build.noindex/Build/Products/Debug"
/usr/bin/pluginkit -r "$product/QuotaClock.app/Contents/PlugIns/QuotaWidget.appex" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$product/QuotaClock.app" 2>/dev/null || true
# Core tests do not compile AppText. Exercise the real UI dictionary too, so
# duplicate translation keys fail the build before a broken app is installed.
xcrun swiftc -parse-as-library -I "$product" Sources/Shared/AppText.swift \
  Scripts/check-localization.swift "$product/QuotaCore.o" -o build.noindex/check-localization
build.noindex/check-localization | tee Evidence/localization-check.log
xcrun swiftc -parse-as-library Sources/QuotaClockApp/CodexDesktopSwitch.swift \
  Scripts/check-codex-switch-launch.swift -o build.noindex/check-codex-switch-launch
build.noindex/check-codex-switch-launch | tee Evidence/codex-switch-launch-check.log
xcrun swiftc -parse-as-library -I "$product" Sources/QuotaClockApp/ProviderSetupState.swift \
  Scripts/check-provider-connection.swift "$product/QuotaCore.o" -o build.noindex/check-provider-connection
build.noindex/check-provider-connection | tee Evidence/provider-connection-check.log
/usr/bin/swift test | tee Evidence/core-tests.log
