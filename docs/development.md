# Developing Hum

Hum is a Swift package with no package dependencies. It builds with Swift 6.2
and the Command Line Tools alone; Xcode is optional. For how the code is put
together, see [ARCHITECTURE.md](ARCHITECTURE.md); for the spec it implements,
[DESIGN.md](DESIGN.md).

## Build and test

```sh
swift build                    # debug build
./scripts/test.sh              # run every test
scripts/build-app.sh           # universal release build, wrapped in build/Hum.app
open build/Hum.app
```

`./scripts/test.sh` runs Hum’s tests, with or without Xcode. Its arguments go
to `swift test` as they are: `--scratch-path FOLDER` builds somewhere other
than `.build`, and `--filter WidgetSnapshot` runs only the tests it matches.
`HUM_TEST_ARCH=x86_64` builds and runs them as Intel code, under Rosetta on
Apple silicon; `HUM_TEST_ARCH=arm64` does the same for Apple silicon.

`scripts/build-app.sh release` (the default) builds a universal app, for Apple
silicon and Intel Macs; `scripts/build-app.sh debug` builds the debug
configuration for this Mac’s own processor. `HUM_ARCHS` picks the
architectures for either: `arm64`, `x86_64`, or both, separated by a space.
Each build also makes the widget extension and puts it in
`Hum.app/Contents/PlugIns/HumWidgets.appex`. Both are signed ad hoc with the
Hardened Runtime, the extension first with its own entitlements, then the app
with the Apple Events entitlement, so it behaves like a distributed build. The
app gets the version from `Resources/Info.plist` (or `HUM_VERSION`) and a build
number from the time it was built (or `HUM_BUILD_NUMBER`), and carries the
icon and Help from `Resources/`. `HUM_SCRATCH_PATH` and `HUM_APP_DIR` keep
parallel builds apart.

`scripts/release.sh VERSION` makes the disk image to share; see
[Release](#release). It always builds the app and its widget extension
universal.

## Built with the Command Line Tools

Hum builds with the Command Line Tools alone, and that shaped a few things:

- **No App Intents.** Without Xcode there’s no App Intents metadata step, so
  the widgets’ buttons are links to Hum’s `hum://` URLs rather than intents.
  Medium and large widgets have them; a small widget is one link that shows
  the player.
- **A hand-assembled extension.** SwiftPM has no app-extension product, so the
  widgets are an executable target, `HumWidgets`, compiled with
  `-application-extension`. `build-app.sh` links it as an extension and wraps
  it in `HumWidgets.appex` with its own Info.plist
  (`Resources/HumWidgets/Info.plist`) inside Hum.app.
- **Ad-hoc signing.** Without a team, there are no App Groups, so the
  sandboxed extension reads one fixed folder through a read-only entitlement
  (see [Where Hum keeps things](guide.md#where-hum-keeps-things)).
- **No Xcode-only macros or tools.** Previews use `PreviewProvider`, not
  `#Preview`, and the icon is drawn by `scripts/make-icon.swift` straight into
  an `.icns`.

## Demo mode and launch options

```sh
build/Hum.app/Contents/MacOS/Hum --demo
HUM_DEMO=1 swift run Hum
```

The demo source plays a generated playlist with generated artwork and never
talks to Music or Spotify, so it never triggers an Automation prompt. It keeps
its own settings and history files, separate from your real ones. These are
the switches Hum reads, mainly for demos and screenshots:

| Switch | Effect |
| --- | --- |
| `--demo`, or `HUM_DEMO` set to `1`, `true`, or `yes` | Use the demo source; never touch Music or Spotify |
| `--demo-playing` | Demo mode, starting playback right away |
| `--demo-history` | Demo mode with six months of made-up listening history (the demo’s own file; real history is never touched) |
| `--demo-device NAME` | Demo mode playing on another device: `kitchen`, `living-room`, `phone`, or `headphones` |
| `--demo-attribution NAME` | Demo mode naming a service as the source of its songs. `Spotify` shows what a Spotify listener sees: no Favorite, no devices, and no album or playlist a song plays from |
| `--demo-automation denied\|undetermined\|granted` | Demo mode with that Automation answer for Music and Spotify on Status, so each state can be seen without changing a real permission |
| `--style ID` | Start the demo in a style: `artOnly`, `title`, `minimal` (Text), `compact` (Strip), `wide`, `bigArt`, or `menuBar`. Only the demo’s settings change; without the demo it’s ignored |
| `--pin POSITION` | Pin the player when it’s first placed: `topLeft`, `top`, `topRight`, `left`, `center`, `right`, `bottomLeft`, `bottom`, or `bottomRight` |
| `--appearance system\|light\|dark` | Force an appearance |
| `--player-size N` | Open the player at size N: a square style’s side, or the width of a bar, Wide, or Big Art, kept within the style’s range |
| `--reveal-controls` | Keep the Now controls showing |
| `--surface now\|echo\|status` | Open on a surface, with `echo` for History (`play` and `find`, from earlier versions, open Now) |
| `--reset-window` | Forget the remembered places and sizes |
| `--settings PANE` | Open Settings on `general`, `appearance`, `player` (Behavior), `shortcuts`, `sources`, `echoPrivacy` (History & Privacy), or `hum` (or `about`), in front without taking the keyboard from the app you’re using |
| `--slow-motion N` | Debug builds only: style switches run N times slower, to see or capture one mid-switch |
| `HUM_SUPPORT_DIR=FOLDER` (environment) | Keep settings, history, and caches in that folder instead of your Library (the widget folder stays where it is) |

Debug builds also read `HUM_DEBUG_KEYS`, `HUM_DEBUG_OPEN_HISTORY`, and
`HUM_DEBUG_EXPAND_INSIGHT`, for checks and screenshots; see
[ARCHITECTURE.md](ARCHITECTURE.md#launch-options).

## `hum://` URLs

Hum claims the `hum` URL scheme. The widgets’ buttons use it, and so can
anything else on the Mac:

```sh
open hum://play-pause
```

| URL | Does |
| --- | --- |
| `hum://play-pause` | Play or pause |
| `hum://next` | Next track |
| `hum://previous` | Previous track |
| `hum://shuffle` | Turn shuffle on or off |
| `hum://repeat` | Move to the next repeat mode the app has |
| `hum://show` | Show the player, or its popover in Menu Bar |

The transport, shuffle, and repeat go straight to the music app, without a
window or bringing Hum forward, and an action the app can’t do is ignored. A
URL with anything more (a path, a query, a user, a port) is ignored. If Hum
isn’t running, opening a `hum://` URL starts it, and the action runs once it’s
ready.

## Release

`scripts/release.sh VERSION` makes a disk image to share:

```sh
HUM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
HUM_NOTARY_PROFILE=hum-notary \
scripts/release.sh 1.0.0
```

It runs every test first, as `./scripts/test.sh` does, and stops if one fails;
`--skip-tests` leaves them out, for a tree that has just passed them. It builds
the universal release app, with its widget extension, and the version and a
build number (`HUM_BUILD_NUMBER`, or the time as YYYYMMDD.HHMM UTC). It signs
the widget extension and then the app with the Hardened Runtime and a secure
timestamp, each with its own entitlements, has Apple notarize it, staples the
ticket, and puts it in `dist/Hum-VERSION.dmg` (or `HUM_DIST_DIR`) beside an
Applications shortcut. Then it checks the disk image with
`codesign --verify --deep --strict` and Gatekeeper (`spctl`), checks that the
app and the widget extension in it both have code for Apple silicon and Intel,
and prints its SHA-256.

The disk image opens in Finder’s standard icon view. To give it a fixed window
instead, with Hum on the left and Applications on the right at a large icon
size, add `--dmg-layout`:

```sh
scripts/release.sh --dmg-layout 1.0.0
```

Only Finder can save a window’s layout, so the script asks it to, through Apple
Events, using only what comes with macOS: the disk image mounts where Finder
sees it, and a Finder window opens on screen for a moment. The first time,
macOS asks whether your terminal may control Finder; allow it, or the script
stops and says how. The window has no background picture: Finder draws the
names under the icons in black in light mode and white in dark mode, and no one
picture keeps both readable. It’s off by default, so a plain release never
touches Finder.

Once, before the first release:

1. Install a **Developer ID Application** certificate in your login Keychain.
   `security find-identity -v -p codesigning` shows its full name, which is
   `HUM_SIGN_IDENTITY`.
2. Save notarization credentials as a keychain profile, with an app-specific
   password from [account.apple.com](https://account.apple.com):

   ```sh
   xcrun notarytool store-credentials hum-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID
   ```

   The profile name (`hum-notary` here) is `HUM_NOTARY_PROFILE`.

Without `HUM_SIGN_IDENTITY`, the script still makes the disk image, signed ad
hoc, and says loudly that it isn’t notarized. Without `HUM_NOTARY_PROFILE`,
it signs but doesn’t notarize, and on other Macs Gatekeeper stops it the
first time it opens, until someone chooses Open Anyway in System Settings ›
Privacy & Security.

## The icon and Help

- `swift scripts/make-icon.swift` draws the icon at every size and writes
  `Resources/AppIcon.icns`. The mark, Vibrato in Hum Crimson, has its SVG
  masters and usage guide in `design/logo/`.
- `Resources/Help/index.html` is Hum Help: the guide’s
  [Using Hum](guide.md#using-hum) section, plus a short version of
  [Music, Spotify, and the demo](guide.md#music-spotify-and-the-demo). Keep
  them in step; a test compares the two key tables, and another checks that
  Help lists every key in DESIGN.md §4.3.

## Diagnostics

Hum logs to the unified log under the subsystem `com.millerroberts.hum`, with
the categories `sources`, `library`, `history`, `window`, and `app`.
Track, artist, and playlist names are private.

```sh
log stream --level debug --predicate 'subsystem == "com.millerroberts.hum"'
```

## Known limits

- **Liquid Glass is unverified on screen.** The macOS 26 materials are built
  against the macOS 26 SDK and kept behind availability checks, but they
  haven’t been seen on a Mac running macOS 26. Everything else has been
  checked on macOS 15.
- **The widget extension is signed ad hoc, and macOS 15 loads it.** On a
  separate Mac running macOS 15.7, an ad-hoc-signed build put all of Hum’s
  displays in the widget gallery (nine then, before three styles retired), and
  the widgets followed the song and their buttons worked. With several copies
  of Hum installed, macOS takes the widgets from the copy with the highest
  build number, whichever folder it’s in. Not yet seen: macOS 26, and the accented and vibrant modes, in which
  the system tints the widgets. A Mac App Store build would need an App Group
  in place of the temporary-exception entitlement.
- **Hum 1.0.0 isn’t notarized.** The disk image on Hum’s page and in the
  Homebrew cask is signed ad hoc, so macOS asks for Open Anyway the first time
  it opens. A notarized build needs a Developer ID identity and a
  notarization profile (see [Release](#release)).

## Repository

```
Package.swift
Sources/
  HumCore/      models, the playback-source protocol, stores, settings, widget data (no UI)
  HumSources/   Music.app, Spotify.app, and the demo source
  HumUI/        the player window, surfaces, styles, Settings, components, design tokens
  Hum/          the menu-bar app: composition root, menu-bar item, global shortcut, hum:// URLs
  HumWidgets/   the widget extension
Tests/HumTests/ Swift Testing suites for Core, Sources, UI, the widgets, and the app shell
Resources/      Info.plist, entitlements, AppIcon.icns, Help/, HumWidgets/
scripts/        build-app.sh, test.sh, release.sh, dmg-layout.swift, make-icon.swift
docs/
  guide.md         using Hum
  development.md   building, testing, and releasing (this page)
  ARCHITECTURE.md  how the code is put together
  DESIGN.md        the design spec
  images/          the pictures in the README
design/logo/    the logo: SVG masters, PNGs, and the usage guide
```
