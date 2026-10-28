#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/test.sh
./Scripts/build.sh
app="$PWD/build/Caffeinate.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
archive="$PWD/build/Caffeinate-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
xcrun notarytool submit -p "${NOTARY_KEYCHAIN_PROFILE:-keys-cli-notary}" "$archive" --wait --timeout 1h
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
echo "Release: $archive"
