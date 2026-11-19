#!/bin/sh
# Build a release of Hum and package it as dist/Hum-VERSION.dmg.
#
#   scripts/release.sh 1.0.0
#   scripts/release.sh --dmg-layout 1.0.0
#   scripts/release.sh --skip-tests 1.0.0
#
# The tests run first (scripts/test.sh), and a failure stops the release.
# --skip-tests leaves them out, for a packaging run of a tree that has just
# passed them.
#
# --dmg-layout also sets the disk image's Finder window: the app on the left
# and the Applications shortcut on the right, at a fixed size. Only Finder can
# save that layout, so it asks Finder to, with Apple Events: the image is
# mounted where Finder sees it, a window opens on screen for a moment, and the
# first run asks to let the terminal control Finder. Without it, Finder shows
# the two items in its standard icon view. See scripts/dmg-layout.swift.
#
# Steps: run the tests, build the release app with the version and a build
# number stamped in, sign it, notarize and staple it, put it in a disk image
# beside an Applications shortcut, and verify the result.
#
# The app and its widget extension are always universal, for Apple silicon and
# Intel Macs: build-app.sh builds each architecture and joins them (HUM_ARCHS
# doesn't apply here).
#
# Environment:
#   HUM_SIGN_IDENTITY    the Developer ID Application identity to sign with,
#                        such as "Developer ID Application: Name (TEAMID)".
#                        Without it the app is signed ad hoc, and on other Macs
#                        it opens only after Open Anyway in System Settings.
#   HUM_NOTARY_PROFILE   a notarytool keychain profile, saved once with
#                        `xcrun notarytool store-credentials`. With it (and an
#                        identity), the app and the disk image are notarized and
#                        stapled.
#   HUM_BUILD_NUMBER     the build number (default: the time, YYYYMMDD.HHMM UTC).
#   HUM_SCRATCH_PATH, HUM_APP_DIR   as for build-app.sh; the tests build in
#                        HUM_SCRATCH_PATH too.
#   HUM_DIST_DIR         where the disk image goes (default dist).
set -eu

cd "$(dirname "$0")/.."

usage="usage: $0 [--dmg-layout] [--skip-tests] VERSION   (for example: $0 1.0.0)"
dmg_layout=false
run_tests=true
while [ $# -gt 0 ]; do
    case "$1" in
        --dmg-layout) dmg_layout=true ;;
        --skip-tests) run_tests=false ;;
        -*) echo "error: unknown option $1" >&2; echo "$usage" >&2; exit 64 ;;
        *) break ;;
    esac
    shift
done
if [ $# -ne 1 ]; then
    echo "$usage" >&2
    exit 64
fi
version="$1"
if ! printf '%s\n' "$version" | grep -q -x -E '[0-9]+(\.[0-9]+){0,2}'; then
    echo "error: \"$version\" isn't a version like 1.0.0" >&2
    exit 64
fi

identity="${HUM_SIGN_IDENTITY:-}"
profile="${HUM_NOTARY_PROFILE:-}"
if [ -n "$profile" ] && [ -z "$identity" ]; then
    echo "error: notarizing needs a Developer ID signature. Set HUM_SIGN_IDENTITY too." >&2
    exit 64
fi

app_dir="${HUM_APP_DIR:-build}"
app="$app_dir/Hum.app"
dist="${HUM_DIST_DIR:-dist}"
dmg="$dist/Hum-$version.dmg"
entitlements=Resources/Hum.entitlements
widget_entitlements=Resources/HumWidgets/HumWidgets.entitlements
build_number="${HUM_BUILD_NUMBER:-$(date -u +%Y%m%d.%H%M)}"

work="$(mktemp -d "${TMPDIR:-/tmp}/hum-release.XXXXXX")"
mounted=""
cleanup() {
    if [ -n "$mounted" ]; then
        hdiutil detach "$mounted" -quiet || hdiutil detach "$mounted" -force -quiet || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

step() {
    printf '\n==> %s\n' "$1"
}

attach() { # attach IMAGE MOUNTPOINT [hdiutil options]
    image="$1" mountpoint="$2"
    shift 2
    mkdir -p "$mountpoint"
    hdiutil attach "$image" -nobrowse -noautoopen -mountpoint "$mountpoint" "$@" > /dev/null
    mounted="$mountpoint"
}

detach() {
    hdiutil detach "$mounted" -quiet || hdiutil detach "$mounted" -force -quiet
    mounted=""
}

# MARK: Test

if [ "$run_tests" = true ]; then
    step "Running the tests"
    scripts/test.sh --scratch-path "${HUM_SCRATCH_PATH:-.build}"
else
    step "Skipping the tests (--skip-tests)"
fi

# MARK: Build

step "Building Hum $version ($build_number)"
HUM_VERSION="$version" HUM_BUILD_NUMBER="$build_number" HUM_APP_DIR="$app_dir" \
    HUM_ARCHS="arm64 x86_64" scripts/build-app.sh release

# MARK: Sign

if [ -n "$identity" ]; then
    step "Signing with $identity"
    # The Hardened Runtime and a secure timestamp are what notarization requires.
    # The widget extension is signed first, with its own entitlements, so the
    # app's signature covers the signed extension.
    codesign --force --sign "$identity" --options runtime --timestamp \
        --entitlements "$widget_entitlements" "$app/Contents/PlugIns/HumWidgets.appex"
    codesign --force --sign "$identity" --options runtime --timestamp \
        --entitlements "$entitlements" "$app"
else
    # build-app.sh already signed it ad hoc, with the same entitlements.
    step "Signed ad hoc"
    cat >&2 <<'EOF'
    **************************************************************
    *  NOT NOTARIZED: HUM_SIGN_IDENTITY isn't set, so this build  *
    *  is signed ad hoc. On other Macs, Gatekeeper stops it the   *
    *  first time it opens, until someone chooses Open Anyway.    *
    *  Set HUM_SIGN_IDENTITY and HUM_NOTARY_PROFILE to notarize.  *
    **************************************************************
EOF
fi
codesign --verify --deep --strict --verbose=2 "$app"

# MARK: Notarize the app

# Stapling the app itself, not only the disk image, lets a copy in
# Applications open the first time without asking Apple's servers.
if [ -n "$profile" ]; then
    step "Notarizing the app"
    ditto -c -k --keepParent "$app" "$work/Hum.zip"
    xcrun notarytool submit "$work/Hum.zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
fi

# MARK: Disk image

step "Making $dmg"
# The window shows the app beside a shortcut to Applications, to drag it onto.
mkdir "$work/stage"
ditto "$app" "$work/stage/Hum.app"
ln -s /Applications "$work/stage/Applications"
# The disk shows Hum's icon in Finder and on the desktop, once its folder is
# flagged as having a custom icon.
cp Resources/AppIcon.icns "$work/stage/.VolumeIcon.icns"
hdiutil create -volname "Hum" -srcfolder "$work/stage" -fs HFS+ -format UDRW \
    -ov "$work/hum-rw.dmg" > /dev/null

setfile="$(xcrun -f SetFile 2> /dev/null || true)"
if [ -z "$setfile" ]; then
    echo "note: SetFile isn't installed (it comes with the Command Line Tools), so the disk keeps the standard icon" >&2
fi
if [ "$dmg_layout" = true ]; then
    step "Laying out the disk image's window"
    # Finder finds the disk by name, so no other disk may be called Hum.
    if [ -e /Volumes/Hum ]; then
        echo "error: a disk named Hum is already mounted. Eject it, then run this again." >&2
        exit 1
    fi
    # Mounted the ordinary way, in /Volumes and visible to Finder.
    rw="$(hdiutil attach "$work/hum-rw.dmg" -noautoopen | awk -F '\t' '$NF ~ /^\/Volumes\// { print $NF }')"
    mounted="$rw"
    if [ "$rw" != /Volumes/Hum ]; then
        echo "error: the image mounted at \"$rw\", not /Volumes/Hum" >&2
        exit 1
    fi
    swift scripts/dmg-layout.swift "$rw"
    # Leave out what the system adds to a volume it has seen.
    rm -rf "$rw/.fseventsd" "$rw/.Spotlight-V100" "$rw/.Trashes" 2> /dev/null || true
elif [ -n "$setfile" ]; then
    attach "$work/hum-rw.dmg" "$work/rw"
    rw="$work/rw"
fi
if [ -n "$mounted" ]; then
    if [ -n "$setfile" ]; then
        "$setfile" -a C "$rw"
    fi
    detach
fi

mkdir -p "$dist"
rm -f "$dmg"
hdiutil convert "$work/hum-rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg" > /dev/null

if [ -n "$identity" ]; then
    codesign --force --sign "$identity" --timestamp "$dmg"
fi
if [ -n "$profile" ]; then
    step "Notarizing the disk image"
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
fi

# MARK: Verify

step "Verifying"
hdiutil verify "$dmg" > /dev/null
attach "$dmg" "$work/verify" -readonly
shipped="$work/verify/Hum.app"
codesign --verify --deep --strict --verbose=2 "$shipped"
shipped_version="$(plutil -extract CFBundleShortVersionString raw "$shipped/Contents/Info.plist")"
shipped_build="$(plutil -extract CFBundleVersion raw "$shipped/Contents/Info.plist")"
if [ "$shipped_version" != "$version" ] || [ "$shipped_build" != "$build_number" ]; then
    echo "error: the disk image holds $shipped_version ($shipped_build), not $version ($build_number)" >&2
    exit 1
fi
for resource in AppIcon.icns Help/index.html; do
    if [ ! -f "$shipped/Contents/Resources/$resource" ]; then
        echo "error: the app in the disk image has no $resource" >&2
        exit 1
    fi
done
shipped_archs="$(lipo -archs "$shipped/Contents/MacOS/Hum")"
for arch in arm64 x86_64; do
    case " $shipped_archs " in
        *" $arch "*) ;;
        *) echo "error: the app in the disk image has no $arch code, only $shipped_archs" >&2; exit 1 ;;
    esac
done
shipped_widgets="$shipped/Contents/PlugIns/HumWidgets.appex/Contents/MacOS/HumWidgets"
if [ ! -f "$shipped_widgets" ]; then
    echo "error: the app in the disk image has no widget extension" >&2
    exit 1
fi
widget_archs="$(lipo -archs "$shipped_widgets")"
for arch in arm64 x86_64; do
    case " $widget_archs " in
        *" $arch "*) ;;
        *) echo "error: the widget extension in the disk image has no $arch code, only $widget_archs" >&2; exit 1 ;;
    esac
done
if [ "$(readlink "$work/verify/Applications")" != /Applications ]; then
    echo "error: the disk image has no Applications shortcut" >&2
    exit 1
fi
if [ "$dmg_layout" = true ] && [ ! -f "$work/verify/.DS_Store" ]; then
    echo "error: the disk image has no window layout" >&2
    exit 1
fi
# Gatekeeper's verdicts, as a downloaded copy would get them. It rejects a
# build that isn't notarized, so without a profile they're only reported.
if [ -n "$profile" ]; then
    spctl --assess --type execute -vv "$shipped"
    spctl --assess --type open --context context:primary-signature -vv "$dmg"
elif [ -n "$identity" ]; then
    spctl --assess --type execute -vv "$shipped" || true
    spctl --assess --type open --context context:primary-signature -vv "$dmg" || true
fi
detach

step "Done"
echo "$dmg: Hum $shipped_version ($shipped_build), $shipped_archs, $(du -h "$dmg" | cut -f1 | tr -d ' ')"
shasum -a 256 "$dmg"
if [ -z "$identity" ]; then
    echo "NOT NOTARIZED: signed ad hoc, so other Macs need Open Anyway the first time. Set HUM_SIGN_IDENTITY and HUM_NOTARY_PROFILE to notarize." >&2
elif [ -z "$profile" ]; then
    echo "NOT NOTARIZED: signed, so other Macs need Open Anyway the first time. Set HUM_NOTARY_PROFILE to notarize." >&2
fi
