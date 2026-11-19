# Architecture

How Hum is put together. The design itself (what things look like, how they
move, and why) lives in [DESIGN.md](DESIGN.md); this document is about the code.

## Modules

```
               ┌────────┐               ┌────────────┐
               │  Hum   │ menu-bar app  │ HumWidgets │ widget extension
               └───┬────┘               └─────┬──────┘
        ┌──────────┼───────────┐              │
        ▼          ▼           │              │
   ┌─────────┐ ┌──────────┐    │              │
   │ HumUI   │ │HumSources│    │              │
   └────┬────┘ └────┬─────┘    │              │
        └─────┬─────┘          │              │
              ▼                │              │
          ┌────────┐ ◀─────────┘              │
          │HumCore │ ◀────────────────────────┘
          └────────┘  models, PlaybackSource, stores, history, settings, artwork, widget data
```

- **HumCore** has no AppKit or SwiftUI, so everything in it can be tested
  without a window. It defines the `PlaybackSource` and `LibraryProvider`
  protocols and the value types that flow through them. It also holds the
  stores that turn sources into what the UI shows (`NowPlayingStore`,
  `LibraryStore`, `ListeningHistory`), plus settings, styles and pins, the
  artwork cache and palette, and what the widgets read (`WidgetSnapshot`,
  `WidgetFiles`, `HumURLAction`).
- **HumSources** implements those protocols for Music.app, Spotify.app, and
  the demo. It is the only module that controls other apps (with Apple
  Events). HumUI only asks `NSWorkspace` to open things the user chose (a
  link, the music app, or a System Settings pane) and, for Status and
  Settings › Sources, for the music apps' own icons (`AppIconLookup`).
- **HumUI** is every window: the player and its three surfaces, the Menu Bar
  style's item and popover, Settings, and Listening History. It depends only
  on HumCore, so it never knows which concrete source is playing: it reads
  `SourceID`, capabilities, and state.
- **Hum** builds everything and wires it together (`HumApp`). It owns the
  status item (`MenuBarController`), the Carbon global shortcut
  (`GlobalHotKeyCenter`), `hum://` URLs (`AppDelegate` and `URLActions`), and
  the main menu (`MainMenu`: Hum, Edit, Window, Help). Hum is a menu-bar app;
  `DockPresence` makes it a regular app, with a Dock icon and that menu bar,
  only while the Listening History window is open. Settings, the player, and
  its popovers never count.
- **HumWidgets** is the widget extension: Art Only, Title, and Text widgets,
  drawn from the snapshot Hum writes. It depends only on HumCore and is
  compiled with `-application-extension`, so it uses only the APIs extensions
  may.
  `scripts/build-app.sh` wraps it in `Hum.app/Contents/PlugIns/HumWidgets.appex`.

| Folder | Holds |
| --- | --- |
| `HumCore/Models`, `NowPlaying`, `Playback` | Source state, commands, the `PlaybackSource` protocol, `NowPlayingStore` |
| `HumCore/Library` | `LibraryProvider`, `LibraryStore` (Play Now, Favorite, devices), thumbnails, backdrop contrast |
| `HumCore/History` | Listens, the recorder, `HistoryStore` (SQLite), insights, sessions, import and export |
| `HumCore/Styles`, `Surfaces`, `Settings`, `Persistence` | Style IDs, shapes and looks, `GlassMaterial`, the three surfaces, `PinPosition`, `HumSettings`, files on disk |
| `HumCore/Widget` | `WidgetSnapshot`, `WidgetFiles`, `WidgetReloadThrottle`, `HumURLAction` |
| `HumCore/Artwork` | Cover cache, palette, and accent |
| `HumCore/Logging` | `HumLog`: the unified-log subsystem and its categories, `sources`, `library`, `history`, `window`, and `app` |
| `HumSources/Scripted`, `Music`, `Spotify`, `AppleEvents` | The scripted app sources, the Apple Event runner, and `AutomationPermissionCheck` |
| `HumSources/Library` | Music's and the demo's library providers |
| `HumSources/Demo` | The demo source and covers |
| `HumUI/Design` | Tokens and primitives (DESIGN.md §5) |
| `HumUI/Now`, `Echo`, `Status` | One folder per surface (`Echo` is History's); `Echo` also holds the Listening History window |
| `HumUI/Styles` | `PlayerLook`, the style switch, the other Now layouts, and `Styles/Shared` |
| `HumUI/MenuBar` | The Menu Bar style's item view and popover, and Hum's mark |
| `HumUI/Components` | Pieces several surfaces share: the HUD, the device picker, the backdrop, missing artwork |
| `HumUI/Window`, `Surfaces`, `Interaction`, `Root` | The player window, pins and throwing, paging, reveal state, the root view |
| `HumUI/Widget` | `WidgetSnapshotWriter` |
| `HumUI/Settings`, `Environment` | The Settings window; `AppServices`, `PlayerActions`, environment keys |
| `HumWidgets` | The widget bundle, its timeline provider, and the displays |

### Concurrency

Swift 6 language mode, strict checking. HumCore, HumSources, and HumWidgets
use approachable concurrency (`async` stays on the caller's actor unless
marked `@concurrent`). HumUI and Hum are main-actor by default. Their pure
types (metrics, key maps, physics, geometry, menu models, Status rows) are
marked `nonisolated` so tests and background work can use them. Environment
keys are written out by hand (`EnvironmentKey` plus an `EnvironmentValues`
property) because the Command Line Tools ship without the macro plugins
`@Entry` needs.

Slow work never runs on the main actor:

- Apple Events go through `AppleScriptRunner`, an actor whose executor is one
  dedicated serial queue. Every `NSAppleScript` is compiled and run there, in
  process. There's no `osascript` subprocess.
- `ArtworkCache` and `ThumbnailCache` are actors. They decode, measure palettes,
  and do file I/O off the main actor.
- `HistoryStore` is an actor that owns the SQLite connection. The stores on the
  main actor only queue work for it and publish what comes back.
- `WidgetSnapshotWriter` encodes covers off the main actor and writes in order.

## Data flow

```
 Music.app  ──┐ PlaybackSource                           ┌─▶ Now, the styles, the menus, Status
 Spotify.app ─┼──── SourceState ────▶ NowPlayingStore ───┤
 Demo       ──┘                        │       │         ├─▶ WidgetSnapshotWriter ─▶ widget folder ─▶ HumWidgets
                                       │       │ events  └─▶ ListeningHistory ─▶ EchoSnapshot ─▶ History
                                       │       ▼                    │
                                       │  ListeningRecorder ─▶ HistoryStore ─▶ the History window
                                       ▼ active source
 LibraryProvider (per source) ◀── LibraryStore ─▶ Play Now, Favorite, devices

 widget link ─▶ hum://… ─▶ AppDelegate (kAEGetURL) ─▶ HumApp.perform ─▶ URLActions ─▶ NowPlayingStore.send
```

Playback state flows one way: sources push `SourceState`, `NowPlayingStore`
merges it into one displayed state, and every view reads the store. Commands go
back the other way through `NowPlayingStore.perform(_:)` or `send(_:)`
(transport, volume, seek) or `LibraryStore` (Play Now, Favorite, devices). No
view talks to a source.

## Composition: `HumApp` and `AppServices`

`HumApp` is the composition root. In order, it:

1. Loads `SettingsStore` (`--style` changes only the demo's settings).
2. Creates the sources for this launch: the demo alone, or Spotify.app and
   Music.app.
3. Starts `NowPlayingStore` over those sources.
4. Opens `HistoryStore` and wraps it in `ListeningHistory`.
5. Builds a `LibraryStore` with a `LibraryProvider` for each source that has
   one: `DemoLibrary`, or `MusicLibrary`. Spotify has no provider; its songs
   play through the source itself (`SourceSongProvider`).
6. Creates the windows: the player, Settings, and Listening History.
7. Creates `MenuBarController`, which builds `MenuBarPopover` on first use, and
   `WidgetSnapshotWriter`.

`start()` installs the global shortcut, starts the stores, the widget writer,
and the player, and opens Settings when `--settings` asks. It then keeps
settings and the store in step through observation loops: the preferred and
last active source, and the registered global shortcut.

`AppServices` carries the shared objects beyond the store and settings. A
feature calls `provide(_:)` once with its `@Observable` object, and every window
(player, Menu Bar popover, Settings, History) wraps its root view in
`inject(_:)`, so all of them see the same objects. Today these are:

- `ListeningHistory`
- `LibraryStore`
- `GlobalShortcutStatus`
- `HistoryWindowPresenter`
- `PlayerSizing`
- the demo's attribution, as an environment value

Everything is provided before the first window renders. A window that has
already rendered doesn't pick up later objects. Views read services as
optionals (`@Environment(LibraryStore.self) private var library: LibraryStore?`)
where a preview or the Settings player preview may run without them.

App-level actions a view can trigger, such as opening Settings on a pane,
hiding the player, showing a surface, or suspending the global shortcut while
one is recorded, come through `PlayerActions`. No view knows about windows or
the app.

## Playback

```
 Music.app  ──┐  distributed notifications (no permission needed)
 Spotify.app ─┼─ Apple Events via AppleScriptRunner (after permission)
 Demo       ──┘  generated playlist and artwork, never touches other apps
        │
        ▼  SourceState (availability, permission, capabilities, snapshot)
 NowPlayingStore ── SourceSelector picks the source to follow
        │           PendingIntents shows commands optimistically
        │           PositionClock runs the position between reports
        ▼
 HumUI reads store.snapshot, store.capabilities, store.position(at:)
```

### Sources

A `PlaybackSource` is a main-actor object that pushes finished `SourceState`
values through `onStateChange`. It declares `SourceCapabilities`, and the UI
shows only what a source can do. Controls it lacks are left out, not disabled.

`ScriptedAppSource` serves both Spotify and Music, configured by a
`ScriptableMusicApp` description. For Spotify it is the only way in: Hum
reaches Spotify through Spotify.app's scripting and the notifications it
posts, and nothing else (DESIGN.md §1.3). `SpotifyApp` declares no favorite,
since Spotify's dictionary has none; `repeatOneByRestart`, since its repeat is
only on or off (see The store); and `canPlaySongs`, so a Spotify song from
History or Listening History plays one at a time by its URI. State arrives
cheapest first:

1. **Distributed notifications** the app posts on track and play-state changes.
   These need no permission, so track names appear before Automation is granted.
2. **A state query** (one Apple Event round trip) after a notification that left
   gaps, after a command, when the player appears or the pointer enters it, and
   when the app leaves the front.
3. **A poll**, as `PollPolicy` decides. It never runs without permission.
   While the app is frontmost it runs every second, playing or paused, because
   shuffle, repeat and volume change there without a notification. Otherwise
   it never runs while paused, and normally runs only once near the end of a
   track, or every 20 s to pick up unannounced changes.

Spotify answers a setter before it takes the value, so a read in the next half
second can report the old one. `SetterHold` keeps each shuffle, repeat,
volume or position Hum set in place of the app's for 1.5 s, until a reply
agrees; a new song lets the position go.

A source never launches its app or prompts for permission on its own. Only a
play command may launch the app, and only a user action may cause the macOS
Automation prompt (`requestAutomationPermission()`, from Allow… on Status or
the first control used).

`DemoSource` behaves like a well-mannered real source, with a little latency and
every capability (Spotify's set, `spotifyCapabilities`, under
`--demo-attribution Spotify`; DESIGN.md §1.3), but does no work while paused
and never talks to another app.
`--demo` or `HUM_DEMO=1` selects it in place of the real sources.

### The store

`NowPlayingStore` (`@Observable`, main actor) owns the displayed state:

- **Selection.** `SourceSelector` is a pure function: an explicitly preferred
  source wins, then whatever is playing, then whatever still has a track, then
  the last active source.
- **Optimistic commands.** `perform(_:)` applies the command to the display at
  once; `send(_:)` does the same without waiting. `PendingIntents` holds each
  changed field against stale reports until the source confirms it or 1.5 s
  pass, when the source's word is final. A failed command rolls back
  immediately. Two unconfirmed reverts of the same kind in a row raise a
  `PlaybackWarning`, which Now shows as a banner.
- **Position.** `PositionClock` keeps the last reported position and the time
  it was true, so the seek bar runs locally and the source is never polled for
  it.
- **Artwork.** Covers are fetched once per track, decoded and measured by
  `ArtworkCache`, and published with their `ArtworkPalette`. Every cover gets
  the same treatment, whatever its source (DESIGN.md §13.17). The cache keeps
  the 300 covers used last on disk, trimming once each run, at its first
  lookup or insert, and again after every 20 new covers.
- **Events.** `addObserver(_:)` returns a `NowPlayingObservation` that receives
  each `NowPlayingEvent`: track changes with the time heard (kept by a
  `ListeningTally`), play-state changes, seeks, and source changes.
  `ListeningHistory` is the main observer.
- **Repeat one by restart.** For a source with `repeatOneByRestart`
  (Spotify's app, whose repeat is only on or off), One is Hum's own
  (`RepeatOneRestart`). The store keeps the app's repeat on and shows `.one`.
  About two seconds before the song ends it reads the player again and, if
  the same song is playing, sets the position back to 0; if the song ends
  anyway, it goes back with Previous Track, once. The seek sets the store's
  clock back to 0 at once, so before sending it the store notes the song's old
  end: the song giving way to another until just past then means Spotify took
  the new position too late, and counts as the song ending. Each restart sends a `trackChanged`
  with the same song as previous and current, so History counts every time
  through; an observer for whom a restart isn't a new song compares the IDs,
  as `PlayerWindowController` does. One isn't kept when Hum quits: it comes
  back as All.

The store takes `now` and `sleep` closures, so tests drive time with a fake clock.

## Songs beyond Now: `LibraryStore`

Hum has no library browsing or search of its own (DESIGN.md §13.9).
`LibraryStore` (`@Observable`, main actor) is what's left of the library
layer: what Hum does with a song beyond Now's controls, for whichever source
is active.

- **Play Now** on History's and the Listening History window's songs. A source with a
  `LibraryProvider` plays through it: `MusicLibrary` through Music's
  AppleScript (parsed by `MusicLibraryParsing`), `DemoLibrary` through
  `DemoSource`. A source with no provider that can start a song by its ID, as
  Spotify's app can, gets `SourceSongProvider`, which plays one song at a time
  through the source. A song with no way to play has no Play Now, never a
  button that does nothing.
- **Favorite** on any song, with the HUD's confirmation (`LibraryNotice`).
- **Devices**, for the device picker: asked for when the picker opens, and
  again when what plays changes, at most every 15 seconds.
- **Copy Link · Show in App**, in the track menu, from the source's links.
- **Failures.** A request that fails stays as a `LibraryFailure`, with Try
  Again when repeating could help, until it's dismissed or the library follows
  another source. Requests throw `LibraryError` in words the UI shows as they
  are, and the words never name the app on the player.

Each provider declares what it can do right now in `capabilities`, which may
change at any time, and calls `onChange` when it does. The UI shows only
controls whose capability is there, so a provider is only asked for what it
declared. Nothing polls.

Row pictures in History and the Listening History window come from
`ThumbnailCache`, decoded once at the size they're drawn. History sits over the
blurred cover (`SurfaceBackdrop`), and `BackdropContrast` measures text against
the hardest part of that backdrop to read on.

## History: the listening record

```
 NowPlayingStore ── events, snapshot ──▶ ListeningRecorder ── Listen, PendingListen ──▶ HistoryStore (SQLite)
                                          (in ListeningHistory)                              │
                                                                                             ▼
 History ◀────────────── ListeningHistory.echo ◀── EchoSnapshot ◀── InsightEngine, SessionBuilder
```

- **Recording.** `ListeningRecorder` follows `NowPlayingEvent`s and the store's
  snapshot and keeps its own count of time heard. Paused time and time asleep
  (`HistorySleepObserver` reports sleep and wake) never count. It's pure state
  with callbacks. When a song ends, `PlayRules` decide whether the listen
  counts as a play and how it ended, and the finished `Listen` goes to the
  store. While a song plays, a `PendingListen` checkpoint is saved, so a crash
  or a dead battery loses nothing; the next launch recovers and finishes it.
  A listen keeps the album or playlist it played from only when its own
  source reports one. Spotify's app never does, so a Spotify listen has none,
  and History's insights about albums and playlists come from Music's
  listening only (DESIGN.md §6.5).
- **Storing.** `ListeningHistory` (`@Observable`, main actor) owns the recorder
  and queues writes to `HistoryStore` in order. On quit it writes anything
  still queued directly, waiting at most two seconds. It also carries out the
  privacy controls: pause collection (nothing heard while paused is ever
  written), remove with undo, erase everything, import (`HistoryImport`, from
  Spotify's data download), remove what was imported, and export
  (`HistoryExportFormat`). `revision` is bumped after every change, so pages
  reload.
- **The file.** `HistoryStore` is an actor over one SQLite file
  (`SQLiteDatabase`, WAL), with tables for plays, the pending listen, and
  metadata. `HistorySchema` runs numbered migrations, each in a transaction,
  and records the last in `PRAGMA user_version`; migration 2 does nothing
  now, and stays so a file that reached it still opens. A file written by a
  newer Hum is never altered: `openOrFallback(url:)` keeps history in memory
  for that run and reports `storageProblem`. Queries include `top` (songs, artists, or
  albums), `rediscover`, `dailyTotals`, `listens(matching:calendar:)` (a
  `HistoryQuery`), `spans`, and `export`.
- **Indexes.** `plays_by_song` (song, then start) serves the snapshot's
  per-song lookups, first heard included, one song at a time. `plays_imported`,
  a partial index of the imported listens, serves the imported summary and
  Remove Imported. `HistorySchema.addIndexes` adds indexes like it with
  `CREATE INDEX IF NOT EXISTS`, outside the numbered migrations, so
  `user_version` stays where it was and an older Hum still opens the file.
- **Importing.** `HistoryImport` parses Spotify's files, then drops the
  listens already stored. `matching` compares off the store's actor, against
  the stored listens indexed by song, track and title, each in order of start
  time, so a claim looks only at the listens near it in time. The store counts
  its changes (`playsRevision`), and the import compares again if the history
  changed meanwhile. A finished import checkpoints the log
  (`wal_checkpoint(TRUNCATE)`), so it doesn't stay the import's size.
- **Leaving nothing behind.** `secure_delete` is on, so SQLite overwrites what
  it deletes with zeros, even if nothing else runs after it. Remove Imported and
  Erase All History then `VACUUM` and checkpoint, so the file shrinks to what's
  left. Removing a few listens doesn't `VACUUM`; their content is zeroed all
  the same.
- **The snapshot.** `ListeningHistory.refresh()` runs on each track change. It
  asks `HistoryStore.echo(track:inProgress:now:calendar:)` for an
  `EchoSnapshot`: insights about the song playing and the session it belongs
  to, counting the listen in progress. `InsightEngine` (pure, scored by
  relevance) and `SessionBuilder` (pure, splits listening into sessions) do the
  work. `echo` is published only when it changes. Insights over imported
  history say “imported”, never the app's name.

Views:

- `EchoSurface` shows at most two cards from the snapshot: an `InsightCard` and
  a `SessionCard`, built on `SessionRibbon` and `MiniTimeline`.
- The Listening History window is `HistoryWindowPresenter` and
  `HistoryWindowView`. It has one `HistorySection` per page: This Week (a
  `WeekReceipt`), Calendar (`HeatCalendar`), History, Top, and Rediscover.
  Each page scrolls under the toolbar with a hard edge
  (`HistoryPage.historyScrollEdge()`): the system's on macOS 26, a clip
  before it. The window opens with its sidebar collapsed
  (`HistoryWindowPresenter.initialColumnVisibility`, `.detailOnly`), and the
  presenter keeps `columnVisibility` as people leave it while Hum runs.
- History's filters (Any Artist, Any Album, Any Playlist, Any Time) and Top's
  period are `PillMenu`s, DESIGN.md §5.9's family 10: a system menu drawn as
  family 9's capsule (`PillMenuButtonStyle`, from `ActionButtonLook`), in the
  accent while a filter is set. Any Playlist shows only when a listen has a
  playlist.
- `HeatCalendar` takes the keyboard for its arrow keys without a focus ring
  of its own (`focusEffectDisabled()`): the selected day's ring shows where
  the keyboard is.
- Rediscover rows play through `RediscoverPlay`. A song from the active
  source, when it can play songs, plays by its ID. Otherwise the row has no
  button.
- Settings › History & Privacy embeds `EchoSettingsSection`.

The demo keeps its own database (`History-Demo.sqlite`). `--demo-history`
refills it with six months of `DemoHistory`.

## Status: the permission check

`StatusSurface` (DESIGN.md §6.3) has two cards. **Connected to** is
`StatusConnection`: the source the store follows, its icon, and a status line
from its `SourceState`. The icon is the app's own, Spotify's included, read
from its bundle through `AppIconLookup` (DESIGN.md §13.22); the generic
application icon stands in when the app isn't installed, and Hum's for the
demo. **Apps** is one `AppAccessRow` per app, Music then
Spotify, each a pure value whose state, words, glyph, and button are tested.

```
 StatusSurface .onAppear / NSApplication.didBecomeActiveNotification
        │
        ▼
 AppAccessRow.refreshPermissions(in:)        (skipped in the demo)
        │  for each app's source
        ▼
 PlaybackSource.refreshAutomationPermission()
        │  ScriptedAppSource: only while the app is running
        ▼
 AutomationPermissionCheck.determine(bundleIdentifier:ask: false)
        │  AEDeterminePermissionToAutomateTarget, never prompts
        ▼
 SourceState.permission ──▶ AppAccessRow.access(availability:permission:)
```

`access(availability:permission:)` maps the source's state to the row:

| Availability, permission | Row | Action |
| --- | --- | --- |
| not installed, anything | Not installed (dimmed) | none |
| anything, granted or not required | Allowed | none |
| anything, denied | Not allowed | Open System Settings… (Privacy & Security › Automation, through `PermissionGuide`) |
| not running, not determined or unknown | Not open | none: macOS reports a permission only while the app runs, and Hum never opens an app to ask |
| running, not determined or unknown | Not asked yet | Allow…, which calls `requestAutomationPermission()` and so macOS's prompt |

A check that comes back unknown leaves the last answer in place. Nothing runs
on a timer. In the demo, `--demo-automation` sets every row's answer, and
Allow… marks a row allowed without asking macOS.

## The player window

`PlayerWindowController` owns a borderless, non-activating `PlayerPanel`, so
clicking the player never pulls focus from the app you're working in. Inside,
`PlayerHostingView` hosts SwiftUI and tracks the pointer even while Hum is
inactive, so hover works without a click first. `PlayerContentView` clips it to
the player's shape on the layer, so the window shadow follows the corners, and
holds the window's Liquid Glass when there is one (see Liquid Glass).

The controller's collaborators:

| Type | Job |
| --- | --- |
| `PlayerVisibilityController` | Always, On Track Change, On Request, or tucked Under Menu Bar |
| `PlacementResolver` | Pure geometry: a pin's frame on a display, holding the pinned point through size changes, and placements from before pins |
| `SnapProjection` | Pure math: where a throw comes to rest, and the nearest pin there, across displays |
| `WindowMover` | Drag with a kept grab offset, rubber-banding at the screen edges, throw-to-snap with velocity handoff, haptic on landing |
| `WindowMemory` | Per-display placement (with its pin), per-style sizes, and the tucked position |
| `ResizeHandleView` | Resizing in the style's shape; a bar, Wide, or Big Art changes only its width, and a bar or Wide takes the drag only at its sides (`StyleShape.resizesSideways`) |
| `PinchResizeTracker`, `SwipeVolumeTracker` | Pinch between size classes; a vertical two-finger swipe on the cover sets the volume |
| `PlayerExpansion` | Grows Title, Text, Strip, and Wide to a square for History and Status, and puts them back |
| `PlayerSizing` | The current style's size and pin, for Settings, Pin to ▸, and `--reveal-controls` |
| `PlayerKeyCommand` | Pure key map (DESIGN.md §4.3) that the window applies |

Presentation materializes: the window fades in while the SwiftUI root scales
from 0.96 and unblurs, anchored toward the nearest screen edge. Tucked mode
slides down from under the menu bar and back up the same way. Under Reduce
Motion both become a plain fade.

Window and surface motion runs on `SpringSolver`, a closed-form damped spring,
driven by `DisplayLinkFrameDriver`. A dropped frame never changes where the
motion goes, and a new gesture can catch the motion mid-flight at its exact
position and velocity. At rest nothing is scheduled.

### Pins

`PinPosition` (HumCore) is the nine places: `topLeft`, `top`, `topRight`,
`left`, `center`, `right`, `bottomLeft`, `bottom`, and `bottomRight`, titled as
macOS's Move & Resize commands title them. Each knows its `column` and `row`,
`rows` groups them for Pin to ▸, `tuckPosition` is the top pin of its column
for Under Menu Bar, and `initial` (Top Right) is where an unplaced player
starts.

- **Where a pin is.** `PlacementResolver.frame(for:size:in:)` puts the window
  `pinInset` (`Spacing.l`) inside the display's visible frame, or at its
  center for Center.
- **Holding the pin.** When the size or shape changes (a style switch, a size
  preset, a resize drag, `PlayerExpansion`),
  `frame(resizing:to:pin:in:)` keeps the pinned point still: a Top Right
  player grows down and to the left, a Center one from its center. An
  unpinned player keeps its nearest-third anchor instead.
- **Remembered.** `WindowPlacement.pin` is saved per display with the size, so
  each display keeps its own. A placement saved before pins existed gets the
  pin it sits at, within `migrationTolerance` (`nearestPin`).
- **Choosing.** Pin to ▸ in the player's menu and the Position tile in
  Settings › Behavior call `PlayerSizing.pin(to:)`, which moves the window there
  on `Motion.throwSpring`.
- **Throwing.** `WindowMover` hands its release velocity to
  `SnapProjection.target(origin:size:velocity:visibleFrames:among:)`, which
  projects the rest point with a deceleration of 0.998, takes the display
  containing it (or the nearest), and picks the nearest pin there; Under Menu
  Bar limits the choice to the top row. The window settles there on
  `Motion.throwSpring`, carrying the velocity, and one alignment haptic fires as it
  lands. With Snap when thrown off (`BehaviorSettings.snapToCorners`), the
  window stays where it was dropped, with no pin.
- **Displays change.** When a display, the Dock, or the menu bar changes, a
  pinned player moves back to its pin on the display it's on, and an unpinned
  one is kept on screen.

### Surfaces

`SurfacePager` holds a fractional page position. Two-finger swipes move it 1:1,
the ends rubber-band, and a release springs to the page the flick was heading
for, at the fingers' velocity. Clicks on the page indicator use a critically
damped spring; keyboard changes are instant. `PageIndicator` shows only when
the page changes (DESIGN.md §6, §13.21): from the moment a swipe starts
tracking, and on ⌘1–⌘3, Show ▸ or Esc back to Now, until 1.5 s after the page
settles. While hidden it takes no clicks and VoiceOver doesn't see it. `SurfaceContainer` renders the
pages side by side from that position, building only the ones on screen.

`SurfaceView` is the one place that knows all three surfaces, and each owns its
folder: `NowSurface`, `EchoSurface`, and `StatusSurface`.
`SurfacePlaceholder` remains only for a surface whose service is missing, such
as History when no history store could be opened. A surface saved as `"play"` or
`"find"` by an earlier Hum opens Now (`Surface(storedValue:)`).

## Menu Bar mode

The Menu Bar style (DESIGN.md §7.1) has no window: the status item is the
player.

- **Going in.** `AppearanceSettings.style` records `lastWindowStyle` whenever
  it changes from a window style to `.menuBar`. `PlayerWindowController` sees
  the style change, saves the window style's placement, and hides the window
  toward the status item (`statusItemFrame`, from `MenuBarController`) with
  materialize.
- **The item.** `MenuBarController` embeds a `MenuBarPlayerItemView` in the
  status item's button: an 18 pt cover, the title tail-truncated at 160 pt, and
  play/pause and next as template glyphs. Outside Menu Bar the item is
  `HumMark`, Hum's mark as an 18 pt template image, dimmed when no music app is
  available.
- **Clicks.** Outside Menu Bar a click opens the lean menu, rebuilt each time it
  opens. In Menu Bar a click toggles `MenuBarPopover`, and a right-click or
  Control-click opens the lean menu, with Pop Out Player in place of Show
  Player.
- **The popover.** `MenuBarPopover` is a `.transient` `NSPopover` holding
  `MenuBarNowView` with the player's environment and services. Hum comes
  forward while it's open, so it takes Esc, and gives the keyboard back to the
  app that was in front when it closes.
- **Toggle Player.** The global shortcut and Show Player call
  `player.onSummonInMenuBar`, which `HumApp` points at
  `MenuBarController.togglePopover()`. Visibility modes don't apply.
- **Popping out.** Pop Out Player sets the style back to `lastWindowStyle`
  (Art Only if there's none), and the window materializes from the status
  item to its pin.

### Line Apps

Line Apps (its own repository, `line-apps`) is the bundle's menu-bar line: a
click collapses the family's icons into it. `LineAppsFold`
(`Sources/Hum/LineAppsFold.swift`, the same file in Tuck, Pulse and Glow; the
line-apps copy, `Shared/LineAppsFold.swift`, is the one to change first) hears
its distributed notifications (`com.millerroberts.lineapps.fold` and
`.unfold`) and sets the status item's `isVisible`, fading the button a moment
after the line moves, the nearer the line the sooner.

- **Places.** macOS forgets a hidden item's place and brings it back at the
  far left, so the fold notes `NSStatusItem Preferred Position <autosave
  name>` as the item goes and writes it back just before it shows.
- **While collapsed** the popover closes, `statusItemFrame` is nil (the window
  materializes from its pin instead), `togglePopover()` does nothing, and
  reopening Hum opens Settings in Menu Bar (`HumApp.reopen()`).
- **Only while Line Apps runs.** The state (`folded` in Line Apps' defaults)
  is read at launch only if Line Apps is running, and Line Apps terminating
  brings the item back.
- **Cost.** Three notification observers, and a fourth only while collapsed.

## Widgets

```
 NowPlayingStore, settings
        │  observed
        ▼
 WidgetSnapshotWriter (HumUI) ── WidgetReloadThrottle: at most one write every 2 s
        │  WidgetFiles.write: cover-<token>.png, then snapshot.json, each atomic
        ▼
 ~/Library/Application Support/Hum/widget/        then WidgetCenter.reloadAllTimelines()
        │
        ▼
 HumProvider (HumWidgets) ── WidgetFiles.readSnapshot ──▶ HumEntry ──▶ DisplayView(style:)
        │
        ▼  medium and large: Link(destination: action.url); small: widgetURL(hum://show)
 hum://play-pause|next|previous|shuffle|repeat|show
        │  kAEGetURL Apple Event
        ▼
 AppDelegate ─▶ HumApp.perform(_:) ─▶ URLActions.command(for:capabilities:shuffle:repeatMode:) ─▶ store.send
```

- **The snapshot.** `WidgetSnapshot` holds the song, its play state and
  position (with the time the position was true), shuffle, repeat, the
  actions the source supports, the style, the accent, the cover's palette, and
  the cover's file name. It holds no history, no account, no paths, and no
  source: widgets never name the music app. Decoding is lenient, field by
  field. A file from before 2026-11-08 may also hold History's insight and the
  session's trail, for the retired Data and Session widgets (DESIGN.md
  §13.19); they're ignored, and a retired style reads as none.
- **Writing.** `WidgetSnapshotWriter` writes when the song, the play state,
  shuffle, or repeat changes, and when a song's cover arrives after it or the
  position jumps. Changes inside the 2 s window
  fold into one write carrying the latest state. Progress runs on in the
  widget by itself (`ProgressView(timerInterval:)`), so nothing is written
  while nothing changes. As Hum quits it writes the song paused.
- **The folder.** `WidgetFiles.directory` is
  `~/Library/Application Support/Hum/widget/` in the account's real home
  (`getpwuid`, since inside the sandbox Foundation's home is the container),
  even when `HUM_SUPPORT_DIR` moves Hum's other files. The extension is
  sandboxed, can't see Hum's environment, and reads only that folder, through
  the `temporary-exception.files.home-relative-path.read-only` entitlement in
  `Resources/HumWidgets/HumWidgets.entitlements`. An App Group would need a
  team signature. Keep the path, the entitlement, and
  `WidgetFiles.relativePath` in step.
- **Reading.** `HumProvider`'s timeline has the snapshot as it reads now and,
  while it plays, a second entry at the song's end showing it paused, because
  a running Hum would have written a newer one by then. Its policy is
  `.never`: Hum asks for every reload. No snapshot is Nothing Playing, which
  shows Hum's mark.
- **The widgets.** `HumWidgetBundle` lists three widgets, one for each
  `WidgetDisplay` (Art Only, Title, and Text; the other styles have none),
  each a `StaticConfiguration` from `DisplayWidget` with the style's title,
  a one-line description, and its families (DESIGN.md §7.3). `DisplayView`
  draws each from the pieces in `WidgetParts.swift` and the sizes in
  `WidgetTokens.swift`, where `WidgetType.trackTitle` gives the title
  `trackTitle`'s M size in small and medium widgets and its L size in large
  ones, a step larger than the artist line (DESIGN.md §7.3, §13.20).
  `DemoCover` and `HumEntry.demo(at:)` are the gallery's placeholder.
- **Links, not intents.** The Command Line Tools have no App Intents metadata
  step, so buttons are `Link`s to `HumURLAction` URLs (DESIGN.md §13.16). Hum
  declares the `hum` scheme in Info.plist. `AppDelegate` registers a
  `kAEGetURL` handler in `applicationWillFinishLaunching`, so a URL that
  launches Hum isn't lost, and queues actions until `HumApp` exists.
  `HumURLAction(url:)` is strict: a user, password, port, path, query, or
  fragment makes it nil. `show` calls `player.show()`; the others map through
  `URLActions` (shuffle flips, repeat moves to the source's next mode) and are
  dropped when the source's capabilities don't support them.

## Styles

A style is one choice for both appearances. Everything else about how it looks
is kept per style and per appearance (DESIGN.md §8).

- **`PlayerStyleID`** lists the seven styles in DESIGN.md §7's order: Art
  Only, Title, Text, Strip, Wide, Big Art, and Menu Bar. Text and Strip keep the stored
  names of the styles they replaced (`minimal` and `compact`), so saved
  settings carry over. Glass, Data and Session retired on 2026-11-08
  (DESIGN.md §13.19); a saved `glass`, `data` or `session` no longer decodes,
  so it opens as the default, Art Only (see Settings and persistence).
  `hasWindow` is false only for Menu Bar, and `windowStyles` is the six that
  have one, for Style ▸.
- **`StyleGeometry`** gives each style's `StyleShape`: a `square` (Art Only 168
  to 640), a `bar` of fixed height (Title 72, Text 44, Strip 48) whose width
  can change, Wide's `landscape` (320 to 520 wide, half as tall), or Big Art's
  `portrait` (220 to 420 wide), a card whose height is its width plus
  `bigArtControlsHeight`, 161 pt, for the stack under the cover.
  Only one dimension is dragged: a square's side, or a bar's, landscape's, or
  portrait's width. `defaultSize(for:)` is where each opens, `clamp` brings any size into
  a style's shape, and `PlayerSizePreset` is the three sizes Settings offers.
  `surfaceSide` is the 300 pt square Title, Text, Strip, and Wide grow to for
  History and Status (`isBar`, `isLandscape`).
- **`StyleLook`** is one style's look in one `LookAppearance`:
  - the accent (`AccentSource`), the corner radius scale, and the resting
    opacity;
  - which `HoverControls` appear, and the `ProgressIndicator` shown at rest;
  - whether the artwork shows, and the album tint.

  Values are clamped, so no stored combination draws an ugly player.
  `StyleLook.builtIn(for:in:)` is what a style ships with. `AppearanceSettings`
  stores only the user's edits, as a `LookOverride` holding just the fields that
  differ. A field the user never touched follows the built-in value, including
  when a later Hum changes it, and Reset Style returns to it.
- **`PlayerLook`** (HumUI) is what the player is drawn with right now: the
  style, its look in the appearance on screen, and whether the window is a bar.
  `PlayerLookProvider` resolves it from settings for the player. The Settings
  `PlayerPreview` puts in its own, so it can show a look the player isn't
  using. Views read `\.playerLook` and never read settings to decide how they
  look. `PlayerRestingOpacity` fades the player back while nothing is using
  it.
- **`NowStyleSwitch`** picks the Now layout:
  - Art Only: `ArtFirstNowLayout`
  - Title: `TitleNowLayout`
  - Text: `TextNowLayout`
  - Strip: `StripNowLayout`
  - Wide: `WideNowLayout`
  - Big Art: `BigArtNowLayout`
  - Menu Bar: `ArtFirstNowLayout`, for the Settings preview; the popover draws
    `MenuBarNowView`.

  Title, Text, and Strip share `BarSupport.swift` and `BarHUD`. Wide and Big
  Art share `CardStack`: the title row with Save and More, the seek bar with
  times, the transport, and the volume row.
  `ControlsPlatter` is the backing the controls sit on over a cover. A style
  change crossfades the layouts on `Motion.styleSwitch` while the window takes
  the new shape on the same spring (`Motion.styleSwitchSpring`), so the two
  read as one movement. Under Reduce Motion the switch is a plain crossfade.

## Liquid Glass

Liquid Glass exists only on macOS 26 (DESIGN.md §13.18). Hum is built against
the macOS 26 SDK with a macOS 15 deployment target, so every use sits behind
`#available(macOS 26, *)`, with a material for macOS 15.

- **The setting.** `GlassMaterial` (HumCore) is `liquidGlass` or `frosted`, in
  `AppearanceSettings.material`. `GlassMaterial.effective` is Frosted wherever
  `isLiquidGlassAvailable` is false, so a setting saved on macOS 26 does
  nothing wrong on macOS 15. Settings › Appearance shows the Material tile only
  on macOS 26.
- **One question.** `LiquidGlass.isOn(_:)` (HumUI) answers whether the
  effective material is Liquid Glass. Everything else asks it, together with
  Reduce Transparency, which always wins with an opaque material.
- **The window.** `WindowMaterialBackground.usesWindowGlass` decides whether
  the player's window itself is the glass. When it is, the SwiftUI background
  is clear and reports `WindowGlassKey`, and `PlayerContentView` puts the
  content in an `NSGlassEffectView`, fading it with the reveal. Views inside
  read `\.isInWindowGlass` and draw a quiet fill rather than glass on glass.
- **Controls and cards.** `.floatingGlass(in:)` and `HumMaterial` give Liquid
  Glass on macOS 26 and a visual-effect material on macOS 15.
  `PlayerButtonStyle`, `Radius`, the HUD, `ControlsOverlay` (whether the
  controls need `ControlsPlatter`), and the History window's filters make the
  same check. The player menu's Pin to ▸ items show symbols only on macOS 26.

## HumUI layers

HumUI follows the layering in DESIGN.md §5: tokens, then primitives, then
components, then surfaces. Each layer uses only the ones below it, and nothing
hard-codes a value a token already names.

1. **Tokens** (`Design/`): `Spacing`, `Radius`, `HumType`, `HumIcon`, `Motion`,
   `HumColor`, `HumMaterial`, `HumShadow`, and `PlayerMetrics`. `PlayerMetrics`
   maps the window side to a size class (S, M, L) and every control to its
   glyph, backing, and hit sizes.
2. **Primitives** (`Design/`):
   - `PlayerButtonStyle`: Hum's own button families of §5.9 (transport,
     toggle, icon, floating play, chip, and card), with press, hold, focus,
     and hit-target rules. Text buttons are system push buttons;
   - `HumSlider` (§5.10);
   - `.floatingGlass(in:)` (see Liquid Glass);
   - `MarqueeText`, `Scrim`, `ArtBackdrop`, `ControlsPlatter`, and
     `DelayedSpinner`.
3. **Components**:
   - `Now/`:
     - `TrackHeader`, `SeekBar`, `TransportRow`, `VolumeControl`, and
       `ArtworkView`;
     - the banners: `PermissionBanner` and `WarningBanner`;
     - `NowEmptyState`;
     - the track menu: `TrackMenu.song` for a song's items and `PlayerMenu`
       for Style ▸, Pin to ▸, Show ▸, Move to Menu Bar, and Hide Player, pure
       models rendered both as a context menu and as the More button's
       `NSMenu`.
   - `Components/`: `HUD`, `DevicePicker`, `SurfaceBackdrop`, and
     `MissingArtwork`.
   - `Echo/`: `InsightCard`, `SessionRibbon`, `MiniTimeline`,
     `HeatCalendar`, and `PillMenu`.
   - `Status/`: `AppAccessRow`.
   - `Styles/Shared/`: `RestingIndicator`, the bars' `BarHUD` and the views
     in `BarSupport.swift`, and the cards' `CardStack`.
4. **Surfaces** (`Now/`, `Echo/`, `Status/`, composed by `Surfaces/`):
   compose components for a size class and style.

Views read the store, settings, `PlayerInteraction` (whether the controls are
revealed, and why), and the services from the environment. Hover controls go
the moment the pointer leaves, on `Motion.conceal` (an ease-out of 0.18 s),
unless a scrub or an open popover holds them.

Previews (§12) are `PreviewProvider`s under `#if DEBUG`, because the Command
Line Tools don't ship the `#Preview` macro. `Design/PreviewSupport.swift`
gives them a demo player: `PreviewGallery` draws a view at S and L, light and
dark (`PlayerPreviewCase.standard`), with the environment the player sets up.

### Color

`HumColor` resolves each semantic color for its context: on material, light or
dark; over artwork, always light on the dark scrim. It also honors Increase
Contrast. The accent comes from `AccentResolver`, which takes the System, Album,
or Custom color and moves its OKLCH lightness until it reaches 3:1 against
where it's drawn. If it can't, it falls back to the system accent.
`AccentTransition` blends between accents through OKLCH when the track changes.
Slider fills stay neutral; the accent marks only state (toggles, saved, focus).

`ArtworkPalette` measures a cover once: a 40×40 redraw, then seeded k-means in
OKLab, so the same cover always gives the same colors. It produces a background,
text colors guaranteed 4.5:1 against it, and an optional accent.

### Accessibility

- **Labels.** Every control has a label and a help tag, and a value where it
  has one. The status item reads “Hum, no music app available” when it's
  dimmed, and Status's rows read as “Spotify, not allowed”.
- **Adjustable controls.** The seek bar and the volume slider are adjustable.
  At S, the volume button is a plain button for VoiceOver:
  - one press opens the slider and moves focus to it;
  - Escape closes it and puts focus back on the button.
- **Hidden controls** are always revealed for VoiceOver.
- **Display settings:**
  - Reduce Motion turns spatial motion into crossfades
    (`Motion.spatial(_:reduceMotion:)`), and `.commitBounce` drops the
    symbol bounce.
  - Reduce Transparency makes materials opaque, Liquid Glass included.
  - Increase Contrast strengthens strokes and materials.
  - Differentiate Without Color adds a dot under toggles that are on.
- **Actions.** `PlayerRootView` exposes Next Surface and Previous Surface as
  accessibility actions.
- **Announcements.** The shortcut recorder posts its quiet conflict line as an
  announcement, so VoiceOver users hear why a chord wasn't taken.

## Settings and persistence

`HumSettings` is one versioned document with a section per concern:

- `behavior` (visibility, Snap when thrown, the swipes), `appearance` (the
  style, `lastWindowStyle`, the mode, the material, and each style's look),
  and `shortcuts` (Toggle Player only);
- `playback`;
- `history`;
- `window`, the per-display placement and pin, per-style sizes, the tucked
  position, and the last surface.

`SettingsStore` holds each section as its own observable property, so a view
that reads appearance doesn't re-render when the window moves. Window memory
isn't observed at all.

Changes are saved 0.4 s after they stop, atomically, through `JSONFileStore`,
and `flush()` writes at once as Hum quits. A file that can't be read is moved
aside (`quarantinedFile`) and the defaults load, rather than the app failing to
start.

Files live under `AppDirectories`, or under the folder `HUM_SUPPORT_DIR` names:

- `Settings.json`, or `Settings-Demo.json` in the demo;
- `History.sqlite`, or `History-Demo.sqlite` in the demo;
- the artwork and thumbnail caches under `Caches` (none in the demo).

The widget folder is apart from these; see Widgets.

**Migration.** Decoding is lenient, so adding a field never needs a migration:

- Each field decodes with `lenient(_:default:)`, and a bad or missing field
  keeps its default instead of discarding the file.
- In a dictionary, one malformed entry drops only itself (`LenientValue`).
- `HoverControls` drops option bits it doesn't know.

`HumSettings.currentSchemaVersion` is bumped only for a change in meaning, and
the old shape is handled in `init(from:)`. Shapes carried forward:

- Before looks were per style, `AppearanceSettings` stored one accent. It's
  folded into every style's overrides in both appearances, so nobody's color
  changes on update.
- Glass, Data and Session retired on 2026-11-08 (DESIGN.md §13.19). A saved
  `glass`, `data` or `session` in `style` or `lastWindowStyle` reads as Art
  Only, the looks saved for them are dropped, and `WindowMemory.styleSizes` is
  decoded key by key, dropping their sizes. The Data style's
  `history.dataStyleInsight` is ignored. The rest of the file loads as it was.
- The surface titled History (DESIGN.md §13.23) is still `.echo` in code and
  `"echo"` when saved. Before it was `echo`, it was saved as `"pulse"`.
  `Surface` decodes that as `.echo`, and `"play"` and `"find"` as `.now`.
- Sections and keys that are gone are ignored and dropped on the next save:
  the `library` section from Play's time, and the global Find shortcut (never
  handed to Toggle Player).

The history database migrates separately (see History).

**The Settings window.** `SettingsWindowPresenter` creates it on first use and
keeps it, following Hum's own appearance mode. `show(pane:activate:)` opens it
on a `SettingsPane`:

- `general`, `appearance`, `player` (titled Behavior), `shortcuts`,
  `sources`, `echoPrivacy` (History & Privacy), and `about` (titled Hum).
  `SettingsPane(argument:)` also takes `hum`, for `--settings hum`.

`SettingsView` draws the sidebar, in the groups of `SettingsSidebarGroup.all`
(General; Player: Appearance, Behavior, Shortcuts; Music: Sources, History &
Privacy; Hum), and the pane. The Hum pane (`HumSettingsPane`) has the icon,
the version, what Hum is, and Quit Hum; About Hum in the main menu opens it. Choices are illustrated tiles
(`StyleTileArt` and the tile art in `SettingsTileArt.swift`); the Appearance
pane previews the real layouts in `PlayerPreview`, or `MenuBarPreview` for
Menu Bar; Position is `PositionTile`, nine targets over a drawn display. The
rows a style shows or hides are pure models in `SettingsChoices.swift`
(`AppearanceRow`, `PlayerRow`). `LoginItem` wraps open at login:
`SMAppService.mainApp`, behind `LoginItemService`.

**The global shortcut.** `GlobalHotKeyCenter` (Hum) registers Toggle Player
with Carbon's `RegisterEventHotKey`, which needs no Accessibility or Input
Monitoring permission.

- **System shortcuts.** It skips a chord macOS already uses, as the public
  symbolic hot key list reports it (`SystemShortcuts`), since that chord would
  never fire. It reports a chord it couldn't claim to `GlobalShortcutStatus`.
- **While recording.** The shortcut is suspended while a `ShortcutRecorder`
  records, and the new chord is registered as recording ends.
- **Turned down.** The recorder keeps the previous chord and says why in one
  quiet line (`ShortcutConflict`) when the new chord is a key the player
  already uses, or is taken by macOS or another app.

## Launch options

`LaunchOptions` parses these, and only these. Most are for demos,
screenshots, and development.

| Flag | Effect |
| --- | --- |
| `--demo`, or `HUM_DEMO` set to `1`, `true`, or `yes` | Use the demo source; never touch Music or Spotify |
| `--demo-playing` | The demo starts playing |
| `--demo-history` | Refill the demo's history with six months of invented listening |
| `--demo-device NAME` | The demo starts out playing on another device: `kitchen`, `living-room`, `phone`, or `headphones` |
| `--demo-attribution NAME` | The demo names a service as the source of its songs. With `Spotify`, in any case, it follows DESIGN.md §1.3's Spotify column for Save, Repeat, and devices, and names no album or playlist a song plays from (in its seeded history too) |
| `--demo-automation denied\|undetermined\|granted` | What the demo's Status page shows macOS answering for Music and Spotify |
| `--appearance system\|light\|dark` | Force an appearance (`AppearanceMode`) |
| `--player-size N` | Open the player at N (a square's side, or a bar's, Wide's, or Big Art's width), within the style's range |
| `--reveal-controls` | Keep the Now controls revealed |
| `--surface now\|echo\|status` | Open on a surface, with `echo` for History; `play` and `find` open Now |
| `--reset-window` | Start from empty window memory |
| `--settings PANE` | Open Settings on a pane after launch, in front without taking the keyboard |
| `--style ID` | Start the demo in a style, by stored name: `artOnly`, `title`, `minimal`, `compact`, `wide`, `bigArt`, `menuBar` (demo settings only) |
| `--pin POSITION` | Pin the player when it's first placed: `topLeft`, `top`, `topRight`, `left`, `center`, `right`, `bottomLeft`, `bottom`, `bottomRight` |
| `--slow-motion N` | Debug builds only: style switches run N times slower, for capturing a frame mid-switch. Compiled out of release builds |

Every `--demo-…` flag implies `--demo`. `HUM_SUPPORT_DIR=<folder>` keeps
settings, history, and caches inside that folder, so development and
screenshot runs never share data with real use or with each other. It doesn't
move the widget folder.

Debug builds also read three variables for checks and screenshots. Release
builds compile them out.

| Variable | Effect |
| --- | --- |
| `HUM_DEBUG_KEYS="cmd-3 down return"` | Sends those keys to Hum's own window, one every 150 ms, once per launch (`DebugKeyScript`); nothing reaches other apps |
| `HUM_DEBUG_OPEN_HISTORY=SECTION` | Opens the Listening History window on `thisWeek`, `calendar`, `history`, `top`, or `rediscover` a second after launch |
| `HUM_DEBUG_EXPAND_INSIGHT=song\|session` | Starts History with that card expanded |

## Testing

```sh
./scripts/test.sh                              # or: ./scripts/test.sh --scratch-path .build-mine
```

That runs Hum's tests, in `Tests/HumTests` (Swift Testing). Its arguments,
such as `--scratch-path` or `--filter`, go to `swift test` as they are.
`HUM_TEST_ARCH=x86_64` runs the whole toolchain as Intel code, so the tests
build and run as Intel code too, under Rosetta on Apple silicon, in their own
folder inside the scratch path. `HUM_TEST_ARCH=arm64` does the same for Apple
silicon.

Tests never touch the network, the Keychain, Music, Spotify, or another app:

- Sources are fakes (`FakeSource`, in `Support/`).
- Settings and history live in memory (`SettingsStore(fileURL: nil)`,
  `HistoryStore(url: nil)`). Tests of what's written to disk (settings files,
  history files, imports and exports, thumbnails, the widget snapshot, the
  help page) use a folder of their own under the temporary directory, and
  remove it.
- Time comes from an injected clock.

The suites, by folder:

- **Core**: source selection, optimistic intents and the failure warning, the
  position clock, the listening tally, capabilities, surface navigation, hot
  key chords, settings persistence (including what earlier versions left
  behind), launch options, palette determinism and contrast, and accent
  fallback.
- **Sources**: notification and state parsing, script templates, poll policy,
  Music and Spotify app descriptions, the demo source and its covers.
- **Library**: Save on Now and its confirmation, device status, retry, the HUD
  notice layer, Music parsing, the demo library, thumbnails, backdrop contrast
  and accent, missing artwork, and track-menu grouping.
- **Spotify**: Play Now for Spotify songs, `LibraryStore` following Spotify,
  and the demo as Spotify.
- **History**: the store and its queries, play rules and sessions, insights and
  summaries, import, provenance, the calendar's month grid, the recorder
  through `ListeningHistory`, demo history, Rediscover's Play, History
  without an album or playlist, and the file itself: what erasing and removing
  leave in it, the log after an import, the indexes the slow lookups use, and
  the duplicate check against a plain reference.
- **Styles**: geometry and shapes, bar layouts, looks and overrides, hover
  room, scrim feathering, player expansion, and the demo's attribution.
- **Window**: pin placement, the host window, the panel, resize handles, and
  the window mover.
- **Widget**: `HumURLAction`, the snapshot and its lenient decoding, the reload
  throttle, the writer, and the widget displays.
- **Settings**: launch options for Settings, panes and their renders, the
  choice models, window memory, keeping clear of the player, and shortcut
  conflicts with Hum's own keys and with macOS.
- **UI**: size classes and control sizing, hit targets, snap projection, the
  key map, the track menu, the page indicator, the Status page's rows,
  gestures, empty-state copy, time formatting, and accent interpolation.
- **Artwork** and **DemoArt**: the cover's average color, labels drawn on it,
  the disk cache's trim, and the generated covers. A `DemoArtTests` timing
  test can fail under heavy load; run it alone to confirm.
- **Shell** (`Tests/HumTests/Shell`):
  - the main menu's titles, order, keys, and actions;
  - the lean menu-bar menu and the status item;
  - `URLActions`;
  - `DockPresence`;
  - `LoginItem`, through a stand-in for `SMAppService`, so no test registers a
    real login item;
  - the app bundle's Info.plist (for Apple silicon and Intel, with the `hum`
    scheme), the widget extension's plist and entitlements, the guide and Help
    keeping the same key table and listing DESIGN.md §4.3's keys, the README
    and the guides linking only to files that exist, and the log categories.

Anything that needs a window, a pointer, or VoiceOver is checked by hand in a
separate test Mac, never against the developer's own apps or accounts.

With only the Command Line Tools installed, Swift Testing lives outside the
default framework search path. `Package.swift` and `scripts/test.sh` add it, so
the same command works with or without Xcode.

## Build scripts

- **`scripts/build-app.sh [release|debug]`** builds the `Hum` and `HumWidgets`
  products and wraps them in `build/Hum.app`, with the extension at
  `Contents/PlugIns/HumWidgets.appex` and its Info.plist from
  `Resources/HumWidgets/`. It signs the extension ad hoc first, with
  `Resources/HumWidgets/HumWidgets.entitlements` (the sandbox and the widget
  folder's read-only exception), then the app with the Hardened Runtime and
  `Resources/Hum.entitlements`, so Apple Events behave as in a distributed
  build, and checks the result with `codesign --verify --deep --strict`. Two
  variables keep parallel builds apart:
  - `HUM_SCRATCH_PATH` picks the SwiftPM build folder;
  - `HUM_APP_DIR` picks where the app lands.

  `HUM_ARCHS` picks the architectures: `arm64`, `x86_64`, or both. A release
  build defaults to both, a universal app for Apple silicon and Intel Macs; a
  debug build defaults to this Mac's own. Each architecture builds on its own,
  in its own folder inside the scratch path, and `lipo` joins them, for the
  app and the extension alike.

  `release.sh` sets two more for it, `HUM_VERSION` and `HUM_BUILD_NUMBER`,
  which stamp the version and build number into both Info.plists.
- **`scripts/test.sh [swift test arguments]`** runs Hum's tests (see Testing),
  adding the Command Line Tools' Swift Testing when Xcode isn't selected.
  `HUM_TEST_ARCH` (`arm64` or `x86_64`) runs them as that architecture.
- **`scripts/release.sh [--dmg-layout] [--skip-tests] VERSION`** runs
  `test.sh` and stops if it fails (unless `--skip-tests`), builds the
  universal app and extension with `build-app.sh` (always both architectures,
  whatever `HUM_ARCHS` says), signs (Developer ID or ad hoc; the extension
  first, with its own entitlements), notarizes when it can, and makes
  `dist/Hum-VERSION.dmg`, checking that the app and the extension in it both
  have both architectures. `--dmg-layout` runs `scripts/dmg-layout.swift`,
  which asks Finder to lay out the disk image's window. Its variables:
  - `HUM_SIGN_IDENTITY`, the Developer ID Application identity (without it,
    the app is signed ad hoc, and other Macs need Open Anyway the first time);
  - `HUM_NOTARY_PROFILE`, a `notarytool` keychain profile, to notarize and
    staple;
  - `HUM_BUILD_NUMBER` (default: the time, `YYYYMMDD.HHMM` UTC);
  - `HUM_DIST_DIR`, where the disk image goes (default `dist`);
  - `HUM_SCRATCH_PATH` and `HUM_APP_DIR`, as for `build-app.sh`; the tests
    build in `HUM_SCRATCH_PATH` too.
- **`swift scripts/make-icon.swift`** draws `Resources/AppIcon.icns` from the
  geometry of the mark in `design/logo/`.
