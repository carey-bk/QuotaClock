#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.10.0
sha=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
dir=build.noindex/sparkle-tools
mkdir -p "$dir"
if [[ ! -f "$dir/Sparkle.tar.xz" ]]; then
  curl --fail --location --retry 3 --connect-timeout 20 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$dir/Sparkle.tar.xz.partial"
  mv "$dir/Sparkle.tar.xz.partial" "$dir/Sparkle.tar.xz"
fi
printf '%s  %s\n' "$sha" "$dir/Sparkle.tar.xz" | shasum -a 256 -c -
tar -xf "$dir/Sparkle.tar.xz" -C "$dir" Sparkle.framework bin LICENSE
