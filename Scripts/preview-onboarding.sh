#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
product="$PWD/build.noindex/Build/Products/Debug"
preview="$PWD/build.noindex/OnboardingPreview.app/Contents"
mkdir -p "$preview/MacOS" "$preview/Resources"
cp "$product/QuotaClock.app/Contents/Resources/Assets.car" "$preview/Resources/Assets.car"
cp "$product/QuotaClock.app/Contents/Resources/AppIconSilver.icns" "$preview/Resources/AppIconSilver.icns"
cp "$product/QuotaClock.app/Contents/Resources/SourceHanSansCN-Regular.otf" "$preview/Resources/SourceHanSansCN-Regular.otf"
cat > "$preview/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.quotaclock.onboarding-preview</string><key>CFBundleExecutable</key><string>OnboardingPreview</string><key>CFBundleIconFile</key><string>AppIconSilver.icns</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -D ONBOARDING_PREVIEW -parse-as-library -I "$product" \
 Sources/QuotaClockApp/*.swift Sources/Shared/*.swift \
 Scripts/preview-onboarding.swift "$product/QuotaCore.o" \
 -framework SwiftUI -framework AppKit -framework WidgetKit -o "$preview/MacOS/OnboardingPreview"
"$preview/MacOS/OnboardingPreview" "$@"
