#!/bin/sh
# Builds Minidisc for the Mac (Mac Catalyst), signed to run locally, and opens it.
# Until the app is signed with the team's provisioning profile, the keychain refuses a locally
# signed Mac build (-34018), so server logins can't be saved yet.
set -eu
cd "$(dirname "$0")/.."
DERIVED="${DERIVED_DATA:-build/mac}"
xcodebuild build -project Minidisc.xcodeproj -scheme Minidisc \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- -quiet
open -n "$DERIVED/Build/Products/Debug-maccatalyst/Minidisc.app"
