#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
product="$PWD/build.noindex/Build/Products/Debug"
preview="$PWD/build.noindex/SurfaceCards.app/Contents"
mkdir -p "$preview/MacOS" "$preview/Resources"
cp "$product/QuotaClock.app/Contents/Resources/Assets.car" "$preview/Resources/Assets.car"
cat > "$preview/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.quotaclock.surface-preview</string><key>CFBundleExecutable</key><string>SurfaceCards</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -parse-as-library -I "$product" \
 Sources/Shared/AppText.swift Sources/Shared/ProviderCard.swift Sources/Shared/ProviderAccountHeader.swift \
 Sources/Shared/AmbientBackdrop.swift Sources/Shared/AmbientDisplay.swift Sources/Shared/MenuCardsView.swift \
 Scripts/render-surface-cards.swift "$product/QuotaCore.o" \
 -framework SwiftUI -framework AppKit -framework WidgetKit -o "$preview/MacOS/SurfaceCards"
"$preview/MacOS/SurfaceCards" "$PWD/Evidence/surface-settings/cards"
