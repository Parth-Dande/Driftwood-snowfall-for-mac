#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

build_dir="${1:-$PWD/build}"
mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd)"
bundle="$build_dir/Driftwood.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$build_dir/module-cache"

# The macOS 27 SDK turns SwiftUI's @State into a macro whose compiler plugin ships with Xcode
# but not with the Command Line Tools. Without it, build against the newest earlier SDK.
sdk="${DRIFTWOOD_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
plugins="$(dirname "$(xcrun -f swiftc)")/../lib/swift/host/plugins"
state_is_macro() {
    grep -qs "macro State()" "$1"/System/Library/Frameworks/SwiftUI*.framework/Modules/*.swiftmodule/*.swiftinterface
}
if [ -z "${DRIFTWOOD_SDK:-}" ] && state_is_macro "$sdk" && ! ls "$plugins" 2>/dev/null | grep -q SwiftUIMacros; then
    for older in $(ls -d "$(dirname "$sdk")"/MacOSX*.*.sdk 2>/dev/null | sort -rV); do
        if ! state_is_macro "$older"; then
            sdk="$older"
            break
        fi
    done
fi

for arch in arm64 x86_64; do
    xcrun swiftc -O -parse-as-library -target "${arch}-apple-macosx14.0" \
        -sdk "$sdk" \
        -module-cache-path "$build_dir/module-cache" \
        Sources/*.swift -o "$build_dir/Driftwood-$arch"
done
xcrun lipo -create "$build_dir/Driftwood-arm64" "$build_dir/Driftwood-x86_64" \
    -output "$bundle/Contents/MacOS/Driftwood"
cp Info.plist "$bundle/Contents/"
cp LICENSE LICENSE-WallFlow "$bundle/Contents/Resources/"
rm -rf "$bundle/Contents/Resources/Artwork"
mkdir -p "$bundle/Contents/Resources/Artwork"
cp Artwork/*.jpg "$bundle/Contents/Resources/Artwork/"
cp Artwork/AppIcon.icns "$bundle/Contents/Resources/"
codesign --force --sign - "$bundle"
printf '%s\n' "$bundle"
