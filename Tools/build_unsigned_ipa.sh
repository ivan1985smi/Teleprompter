#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Teleprompter.xcodeproj"
SCHEME="Teleprompter"
CONFIGURATION="Release"
DERIVED="build/unsigned/DerivedData"
PAYLOAD="build/unsigned/Payload"
OUTPUT="Teleprompter-unsigned.ipa"

command -v xcodebuild >/dev/null 2>&1 || {
  echo "ERROR: xcodebuild not found. Run this on macOS with Xcode installed." >&2
  exit 1
}

rm -rf "$DERIVED" "$PAYLOAD" "$OUTPUT"
mkdir -p "$PAYLOAD"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$(find "$DERIVED/Build/Products/${CONFIGURATION}-iphoneos" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: built .app not found" >&2
  exit 1
fi

cp -R "$APP_PATH" "$PAYLOAD/"
(cd build/unsigned && zip -qry "../../$OUTPUT" Payload)

echo "Created: $OUTPUT"