#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
product="$PWD/build.noindex/Build/Products/Debug"
xcrun swiftc -parse-as-library -I "$product" \
  Sources/Shared/AppText.swift Sources/Shared/ProviderCard.swift Sources/Shared/ProviderAccountHeader.swift \
  Scripts/render-phase4-cards.swift "$product/QuotaCore.o" \
  -framework SwiftUI -framework AppKit -framework WidgetKit -o "$PWD/build.noindex/render-phase4-cards"
"$PWD/build.noindex/render-phase4-cards" "$PWD/Evidence/phase4-cards"
