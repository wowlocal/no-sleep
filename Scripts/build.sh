#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/build/Caffeinate.app"
rm -rf "$app"
mkdir -p "$app/Contents/"{MacOS,Resources}
for arch in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" \
        Sources/*.swift Shared/*.swift \
        -o "build/Caffeinate-$arch" -framework AppKit -framework SwiftUI -framework ServiceManagement
    xcrun swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" \
        Helpers/LidGuard/main.swift Shared/*.swift \
        -o "build/CaffeinateLidGuard-$arch" -framework Security -framework IOKit
done
xcrun lipo -create build/Caffeinate-arm64 build/Caffeinate-x86_64 -output "$app/Contents/MacOS/Caffeinate"
xcrun lipo -create build/CaffeinateLidGuard-arm64 build/CaffeinateLidGuard-x86_64 -output "$app/Contents/MacOS/CaffeinateLidGuard"
cp Info.plist "$app/Contents/Info.plist"
xcrun swift Scripts/MakeIcon.swift "$PWD/build/AppIcon.iconset"
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
identity="Developer ID Application: Misha Kharytonchyk (H8QG3CBM96)"
codesign --force --sign "$identity" --identifier com.mishanevazhno.caffeinate.lidguard --options runtime --timestamp "$app/Contents/MacOS/CaffeinateLidGuard"
codesign --force --sign "$identity" --options runtime --timestamp "$app/Contents/MacOS/Caffeinate"
codesign --force --sign "$identity" --options runtime --timestamp "$app"
codesign --verify --deep --strict --verbose=2 "$app"
echo "Built: $app"
