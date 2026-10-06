#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
product="$PWD/build.noindex/Build/Products/Debug"
[[ -f "$product/QuotaCore.o" ]] || { print -u2 'Run Scripts/build.sh first'; exit 1; }
xcrun swiftc -parse-as-library -I "$product" \
  Sources/Shared/AppText.swift Sources/Shared/ProviderCard.swift Sources/Shared/ProviderAccountHeader.swift \
  Scripts/render-phase31-cards.swift "$product/QuotaCore.o" \
  -framework SwiftUI -framework AppKit -framework WidgetKit -o "$PWD/build.noindex/render-phase31-cards"
"$PWD/build.noindex/render-phase31-cards" "$PWD/Evidence/phase31-cards"
print 'Rendered Evidence/phase31-cards'
