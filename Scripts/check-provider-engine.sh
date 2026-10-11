#!/bin/zsh
# Offline packaged-engine smoke test. No usage requests or real credentials.
set -euo pipefail
cd "${0:A:h:h}"
app="${1:-$PWD/build.noindex/Build/Products/Release/QuotaClock.app}"
engine="$app/Contents/MacOS/QuotaClockProviderEngine"
architectures="$(/usr/bin/lipo -archs "$engine")"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
probe="$(mktemp -d "${TMPDIR:-/tmp}/quotaclock-engine-check.XXXXXX")"
trap 'rm -rf "$probe"' EXIT
HOME="$probe" CODEXBAR_CONFIG="$probe/config.json" CODEXBAR_DISABLE_KEYCHAIN_ACCESS=1 "$engine" config providers --format json > "$probe/providers.json"
python3 - "$probe/providers.json" <<'PY'
import json,re,sys
from pathlib import Path
rows=json.loads(Path(sys.argv[1]).read_text())
ids=re.findall(r'\.init\(id: "([^"]+)"',Path('Sources/QuotaCore/ProviderEngineCatalog.swift').read_text())
assert len(rows)==len(ids)==100
assert {r['provider'] for r in rows}==set(ids)
print('Bundled engine: both architectures; 100 provider IDs match; isolated no-network registry probe passed.')
PY
