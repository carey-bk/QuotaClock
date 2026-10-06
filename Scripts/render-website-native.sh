#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
module="$PWD/build.noindex/website-module"
bundle="$PWD/build.noindex/WebsiteNative.app/Contents"
mkdir -p "$module" "$bundle/MacOS" "$bundle/Resources" "$PWD/Evidence/website/native"
xcrun swiftc -parse-as-library -emit-library -emit-module -module-name QuotaCore Sources/QuotaCore/*.swift \
  -emit-module-path "$module/QuotaCore.swiftmodule" -o "$module/libQuotaCore.dylib"
# Build 78 is the installed source of the compiled asset catalog, never its accounts.
cp /Applications/QuotaClock.app/Contents/Resources/Assets.car "$bundle/Resources/Assets.car"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.quotaclock.website-native</string><key>CFBundleExecutable</key><string>WebsiteNative</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -D ONBOARDING_PREVIEW -parse-as-library -I "$module" -L "$module" -lQuotaCore \
  -Xlinker -rpath -Xlinker "$module" Sources/QuotaClockApp/*.swift Sources/Shared/*.swift Scripts/render-website-native.swift \
  -framework SwiftUI -framework AppKit -framework WidgetKit -o "$bundle/MacOS/WebsiteNative"
"$bundle/MacOS/WebsiteNative" "$PWD/Evidence/website/native"
