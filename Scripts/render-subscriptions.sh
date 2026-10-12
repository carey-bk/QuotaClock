#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
product="$PWD/build.noindex/Build/Products/Release"
preview="$PWD/build.noindex/SubscriptionPreview.app/Contents"
mkdir -p "$preview/MacOS" "$preview/Resources"
cp "$product/QuotaClock.app/Contents/Resources/Assets.car" "$preview/Resources/Assets.car"
cat > "$preview/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.quotaclock.subscription-preview</string><key>CFBundleExecutable</key><string>SubscriptionPreview</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -parse-as-library -I "$product" \
 Sources/Shared/AppText.swift Sources/Shared/ProviderCard.swift Sources/Shared/ProviderAccountHeader.swift \
 Scripts/render-subscriptions.swift "$product/QuotaCore.o" \
 -framework SwiftUI -framework AppKit -o "$preview/MacOS/SubscriptionPreview"
"$preview/MacOS/SubscriptionPreview" "$PWD"
