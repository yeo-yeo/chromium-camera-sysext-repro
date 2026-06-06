#!/usr/bin/env bash
# Generates ChromiumFeedback.xcodeproj with xcodegen.
#
# Usage:
#   DEVELOPMENT_TEAM=ABC1234567 ./scripts/setup.sh

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    if grep -q "DEVELOPMENT_TEAM: TEAMIDXXXX" project.yml; then
        echo "Substituting DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM into project.yml..."
        sed -i '' "s/DEVELOPMENT_TEAM: TEAMIDXXXX/DEVELOPMENT_TEAM: $DEVELOPMENT_TEAM/" project.yml
    fi
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "Installing xcodegen via Homebrew..."
        brew install xcodegen
    else
        cat <<'EOF' >&2
xcodegen is required.

Install it and re-run:
    brew install xcodegen

Or download a release binary:
    https://github.com/yonaskolb/XcodeGen/releases
EOF
        exit 1
    fi
fi

echo "Running xcodegen..."
xcodegen generate

if grep -q "DEVELOPMENT_TEAM: TEAMIDXXXX" project.yml; then
    cat <<'EOF'

WARNING: project.yml still contains DEVELOPMENT_TEAM=TEAMIDXXXX.

Either re-run with:
    DEVELOPMENT_TEAM=YOURTEAM ./scripts/setup.sh

or open ChromiumFeedback.xcodeproj in Xcode and set Signing & Capabilities
for both targets before building.
EOF
fi

cat <<'EOF'

Done.

Next:
  ./scripts/build.sh
  open /Applications/ChromiumFeedback.app
EOF
