#!/bin/zsh
# Builds a Release copy and zips it for a GitHub release. The app is signed with the
# development certificate but not notarized, so first launch needs "Open Anyway"
# (see README). Nothing is uploaded; the command to publish is printed at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
version=$(awk '/MARKETING_VERSION:/ { print $2 }' project.yml)
out=build/release
rm -rf "$out"

xcodebuild -project SmartCalendarClassifier.xcodeproj -scheme SmartCalendarClassifier -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$out/DerivedData" -allowProvisioningUpdates build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

app="$out/DerivedData/Build/Products/Release/Smart Calendar Classifier.app"
codesign --verify --deep --strict "$app"
zip="$out/SmartCalendarClassifier-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

echo "Built $zip ($(du -h "$zip" | cut -f1))"
shasum -a 256 "$zip"
echo
echo "To publish:"
echo "  gh release create v$version \"$zip\" --title \"Smart Calendar Classifier $version\" --generate-notes"
