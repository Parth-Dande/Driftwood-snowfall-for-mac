#!/bin/bash
# Builds Driftwood.app as a universal binary. Usage: ./build.sh [output directory]
set -euo pipefail
cd "$(dirname "$0")"

build_dir="${1:-$PWD/build}"
mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd)"
bundle="$build_dir/Driftwood.app"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

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

sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Sources -name '*.swift' | sort)

for arch in arm64 x86_64; do
    xcrun swiftc -O -parse-as-library -target "${arch}-apple-macosx14.0" \
        -sdk "$sdk" \
        -module-cache-path "$work/module-cache" \
        "${sources[@]}" -o "$work/Driftwood-$arch"
done

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/Artwork"
xcrun lipo -create "$work/Driftwood-arm64" "$work/Driftwood-x86_64" -output "$bundle/Contents/MacOS/Driftwood"
cp Resources/Info.plist "$bundle/Contents/"
cp Resources/AppIcon.icns LICENSE LICENSE-WallFlow "$bundle/Contents/Resources/"
cp Resources/Artwork/*.jpg "$bundle/Contents/Resources/Artwork/"
codesign --force --sign - "$bundle"
printf '%s\n' "$bundle"
