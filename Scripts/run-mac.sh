#!/bin/sh
# Builds the native Mac app (the MinidiscMac target), signed to run locally, and opens it.
# A locally signed build has no team identity, so keychain access can fail (-34018) until the
# app is built team-signed from Xcode.
set -eu
cd "$(dirname "$0")/.."
DERIVED="${DERIVED_DATA:-build/mac}"
xcodebuild build -project Minidisc.xcodeproj -scheme MinidiscMac \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- -quiet
open -n "$DERIVED/Build/Products/Debug/Minidisc.app"
