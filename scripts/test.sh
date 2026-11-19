#!/bin/sh
# Run Hum's tests.
#
#   ./scripts/test.sh                           everything
#   ./scripts/test.sh --scratch-path .build-me  everything, built in .build-me
#   ./scripts/test.sh --filter LibraryStore     only the tests --filter matches
#   HUM_TEST_ARCH=x86_64 ./scripts/test.sh      everything, as Intel code
#
# Arguments go to `swift test` unchanged.
#
# HUM_TEST_ARCH (arm64 or x86_64) runs the whole toolchain as that
# architecture, so the tests build and run as it; on Apple silicon, x86_64 runs
# under Rosetta. Each architecture builds in its own folder inside the scratch
# path. SwiftPM's own --arch can't do this: it builds the tests, but its test
# runner stays native and can't load them.
#
# With only the Command Line Tools installed, Swift Testing ships as a framework
# that SwiftPM's generated test runner can't see, so the runner would build, find
# no tests, and exit quietly. Passing the framework folder to every module fixes
# that. With Xcode selected this is plain `swift test`.
set -eu
cd "$(dirname "$0")/.."

run=""
case "${HUM_TEST_ARCH:-}" in
    "") ;;
    arm64|x86_64) run="arch -$HUM_TEST_ARCH" ;;
    *) echo "error: HUM_TEST_ARCH is \"$HUM_TEST_ARCH\"; it takes arm64 or x86_64" >&2; exit 64 ;;
esac

clt=/Library/Developer/CommandLineTools
frameworks="$clt/Library/Developer/Frameworks"
if [ "$(xcode-select -p 2>/dev/null)" = "$clt" ] && [ -d "$frameworks/Testing.framework" ]; then
    $run swift test -Xswiftc -F -Xswiftc "$frameworks" "$@"
else
    $run swift test "$@"
fi
