#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root on macOS after flutter build ios --no-codesign.
app="build/ios/iphoneos/Runner.app"
test -d "$app"
test -f "$app/Info.plist"
test -d "$app/Frameworks/App.framework"
test -d "$app/Frameworks/Flutter.framework"
test -d build/ios-cores/Frameworks
ditto build/ios-cores/Frameworks "$app/Frameworks"
ditto build/ios-cores/CoreLicenses "$app/CoreLicenses"
for core in fceumm snes9x gambatte mgba; do
  xcrun lipo "$app/Frameworks/$core.framework/$core" -verify_arch arm64
done
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
test -n "$executable"
xcrun lipo "$app/$executable" -verify_arch arm64

staging=$(mktemp -d "${TMPDIR:-/tmp}/vantage-ipa.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Payload" build/ios/ipa
ditto "$app" "$staging/Payload/Runner.app"
ipa="$PWD/build/ios/ipa/Vantage-unsigned.ipa"
ditto -c -k --sequesterRsrc --keepParent "$staging/Payload" "$ipa"
unzip -tq "$ipa"
unzip -Z1 "$ipa" | grep '^Payload/Runner.app/Info.plist$' > /dev/null
(cd build/ios/ipa && shasum -a 256 Vantage-unsigned.ipa > Vantage-unsigned.ipa.sha256)
