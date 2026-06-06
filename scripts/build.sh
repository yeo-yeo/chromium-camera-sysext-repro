#!/usr/bin/env bash
# Builds ChromiumFeedback.app and copies it to /Applications.

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED="$PWD/build"

if [[ ! -d ChromiumFeedback.xcodeproj ]]; then
    echo "ChromiumFeedback.xcodeproj is missing. Run ./scripts/setup.sh first." >&2
    exit 1
fi

echo "Building ChromiumFeedback.app ($CONFIGURATION)..."
xcodebuild \
    -project ChromiumFeedback.xcodeproj \
    -scheme ChromiumFeedback \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    build

APP_BUILT="$DERIVED/Build/Products/$CONFIGURATION/ChromiumFeedback.app"
APP_DEST="/Applications/ChromiumFeedback.app"

if [[ ! -d "$APP_BUILT" ]]; then
    echo "Built app not found at $APP_BUILT" >&2
    exit 1
fi

echo "Installing to $APP_DEST"
rm -rf "$APP_DEST"
cp -R "$APP_BUILT" "$APP_DEST"

echo
echo "Done. Open the app:"
echo "    open $APP_DEST"
