#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
product="$PWD/build.noindex/Build/Products/Debug"
check="$PWD/build.noindex/hero-widget-query"
mkdir -p "$check"
# Compile the exact query/intent declarations; the Widget @main/view are not needed.
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/QuotaWidget/QuotaWidget.swift').read_text()
Path('build.noindex/hero-widget-query/WidgetQueries.swift').write_text(source.split('struct QuotaEntry: TimelineEntry')[0])
PY
xcrun swiftc -parse-as-library -I "$product" "$check/WidgetQueries.swift" \
  Scripts/check-hero-widget-query.swift "$product/QuotaCore.o" \
  -framework SwiftUI -framework WidgetKit -framework AppIntents -o "$check/check"
/usr/bin/codesign --force --sign 'Developer ID Application' --identifier com.quotaclock.hero-query-check \
  --entitlements Config/App.entitlements "$check/check"
"$check/check"
