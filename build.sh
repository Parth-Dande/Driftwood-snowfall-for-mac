#!/bin/bash
# Builds Driftwood.app as a universal binary.
#
#   ./build.sh --install     Build and install, leaving one copy of the app on this Mac.
#   ./build.sh [directory]   Build into a directory (default: build/) without installing.
#
# --install replaces the copy already in /Applications or ~/Applications, or installs into
# /Applications (~/Applications if that is not writable). The build itself happens in a temporary
# directory, so no second Driftwood is left behind for Spotlight and Launchpad to list.
set -euo pipefail
cd "$(dirname "$0")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

install=false
if [ "${1:-}" = "--install" ]; then
    install=true
    build_dir="$work/product"
else
    build_dir="${1:-$PWD/build}"
fi
mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd)"
bundle="$build_dir/Driftwood.app"

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

if ! $install; then
    printf '%s\n' "$bundle"
    exit
fi

if [ -d "$HOME/Applications/Driftwood.app" ] && [ ! -d /Applications/Driftwood.app ]; then
    destination="$HOME/Applications"
elif [ -w /Applications ]; then
    destination=/Applications
else
    destination="$HOME/Applications"
fi
mkdir -p "$destination"
installed="$destination/Driftwood.app"

was_running=false
if pgrep -x Driftwood >/dev/null; then
    was_running=true
    pkill -x Driftwood || true
    sleep 1
fi
rm -rf "$installed"
ditto "$bundle" "$installed"
codesign --verify --deep --strict "$installed"

# Forget the copy an earlier plain build left in build/, so the app is listed only once.
if [ -d "$PWD/build/Driftwood.app" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -u "$PWD/build/Driftwood.app" >/dev/null 2>&1 || true
    rm -rf "$PWD/build/Driftwood.app"
fi
if $was_running; then open "$installed"; fi
printf '%s\n' "$installed"
