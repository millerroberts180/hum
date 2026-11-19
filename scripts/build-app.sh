#!/bin/sh
# Build Hum and wrap it in build/Hum.app, signed ad hoc, with its widget
# extension in Contents/PlugIns/HumWidgets.appex.
#
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build
#
# HUM_SCRATCH_PATH picks the SwiftPM build folder (default .build) and HUM_APP_DIR
# the folder the app lands in (default build), so parallel builds stay apart.
#
# HUM_ARCHS picks the architectures, separated by spaces: arm64, x86_64, or
# both. A release build defaults to both, a universal app for Apple silicon and
# Intel Macs; a debug build defaults to this Mac's own, for speed. Each one
# builds on its own, in its own folder inside HUM_SCRATCH_PATH, and lipo joins
# them.
#
# HUM_VERSION sets the version (default: the one in Resources/Info.plist) and
# HUM_BUILD_NUMBER the build number (default: the time, as YYYYMMDD.HHMM in UTC,
# so each build counts up). scripts/release.sh sets both.
#
# Then: open build/Hum.app   (or build/Hum.app/Contents/MacOS/Hum --demo)
set -eu

cd "$(dirname "$0")/.."

configuration="${1:-release}"
case "$configuration" in
    release|debug) ;;
    *) echo "usage: $0 [release|debug]" >&2; exit 64 ;;
esac

version="${HUM_VERSION:-$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)}"
build_number="${HUM_BUILD_NUMBER:-$(date -u +%Y%m%d.%H%M)}"
# Both are what Launch Services and the About panel expect: one to three
# dot-separated numbers.
for value in "$version" "$build_number"; do
    if ! printf '%s\n' "$value" | grep -q -x -E '[0-9]+(\.[0-9]+){0,2}'; then
        echo "error: \"$value\" isn't a version or build number like 1.0.0 or 20261105.1430" >&2
        exit 64
    fi
done

scratch="${HUM_SCRATCH_PATH:-.build}"
if [ "$configuration" = release ]; then
    archs="${HUM_ARCHS:-arm64 x86_64}"
else
    archs="${HUM_ARCHS:-$(uname -m)}"
fi
# One build per architecture: SwiftPM builds several at once only with Xcode.
# Each builds the app and the widget extension. The extension links as an app
# extension, which allows only the API that's safe in one (its code is compiled
# that way by Package.swift); the flag is given here, not in Package.swift, so
# that the test bundle, which links the extension's code, isn't. Like every app
# extension, it starts at Foundation's NSExtensionMain, which sets up the
# extension and then calls the widget bundle's `@main`; started at `main`
# itself, the extension exits before the system can ask it for its widgets.
count=0
for arch in $archs; do
    case "$arch" in
        arm64|x86_64) ;;
        *) echo "error: HUM_ARCHS names \"$arch\"; it takes arm64, x86_64, or both" >&2; exit 64 ;;
    esac
    swift build --scratch-path "$scratch" -c "$configuration" --product Hum --arch "$arch"
    swift build --scratch-path "$scratch" -c "$configuration" --product HumWidgets --arch "$arch" \
        -Xlinker -application_extension -Xlinker -e -Xlinker _NSExtensionMain
    count=$((count + 1))
done
if [ $count -eq 0 ]; then
    echo "error: HUM_ARCHS names no architecture; it takes arm64, x86_64, or both" >&2
    exit 64
fi

# join PRODUCT OUTPUT: one binary with every architecture's build of PRODUCT.
join() {
    product="$1" output="$2"
    set --
    for arch in $archs; do
        set -- "$@" "$(swift build --scratch-path "$scratch" -c "$configuration" --arch "$arch" --show-bin-path)/$product"
    done
    if [ $# -eq 1 ]; then
        cp "$1" "$output"
    else
        lipo -create -output "$output" "$@"
    fi
}

app="${HUM_APP_DIR:-build}/Hum.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
join Hum "$app/Contents/MacOS/Hum"
cp Resources/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
plutil -lint "$app/Contents/Info.plist" > /dev/null

# Everything else in Resources ships in the bundle: the icon and Help. The
# widget extension's files go into its own bundle, below.
for item in Resources/*; do
    case "$(basename "$item")" in
        Info.plist|Hum.entitlements|HumWidgets) ;;
        *) cp -R "$item" "$app/Contents/Resources/" ;;
    esac
done

# The widget extension (DESIGN.md §7.3): a WidgetKit app extension bundle with
# the same version as the app. Its entry point is NSExtensionMain, linked above.
appex="$app/Contents/PlugIns/HumWidgets.appex"
mkdir -p "$appex/Contents/MacOS"
join HumWidgets "$appex/Contents/MacOS/HumWidgets"
cp Resources/HumWidgets/Info.plist "$appex/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$appex/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$appex/Contents/Info.plist"
plutil -lint "$appex/Contents/Info.plist" > /dev/null

# Ad hoc signatures with the Hardened Runtime, so the entitlements apply exactly
# as they would in a distributed build: the extension first, sandboxed and able
# to read Hum's widget snapshot, then the app around it, with the Apple Events
# entitlement.
codesign --force --sign - --options runtime --timestamp=none \
    --entitlements Resources/HumWidgets/HumWidgets.entitlements "$appex"
codesign --force --sign - --options runtime --timestamp=none \
    --entitlements Resources/Hum.entitlements "$app"
codesign --verify --deep --strict "$app"

echo "Built $app ($configuration, $(lipo -archs "$app/Contents/MacOS/Hum"), widgets $(lipo -archs "$appex/Contents/MacOS/HumWidgets"), version $version, build $build_number)"
