#!/bin/zsh
set -euo pipefail
cd "$SRCROOT"
engine="$SRCROOT/build.noindex/provider-engine/release"
if [[ ! -x "$engine/CodexBarCLI" ]]; then
  print -u2 'Provider engine missing. Run zsh Scripts/build-provider-engine.sh before building the app.'
  exit 1
fi
mkdir -p "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/MacOS"
ditto "$engine/CodexBarCLI" "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/MacOS/QuotaClockProviderEngine"
for resource in "$engine"/*.bundle(N); do
  ditto "$resource" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/${resource:t}"
done
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime --timestamp=none "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/MacOS/QuotaClockProviderEngine"
fi
