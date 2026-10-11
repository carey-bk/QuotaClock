#!/bin/zsh
# Build the pinned, vendored data engine; never invoked by refresh or launch.
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
swift build --package-path Vendor/CodexBar --scratch-path build.noindex/provider-engine -c "$configuration" --product CodexBarCLI --arch arm64 --arch x86_64
