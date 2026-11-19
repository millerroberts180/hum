# Hum guide

Hum is a small, art-first music player for the Mac menu bar. It shows what
Music or Spotify is playing as a floating window of album art, with the
controls appearing on hover, and stays out of the way the rest of the time.

Hum controls Music and Spotify only through their own apps, with Apple Events
and the notifications they post. It never plays audio itself, and there’s no
account to connect.

- [Install](#install)
- [Music, Spotify, and the demo](#music-spotify-and-the-demo)
- [Permissions](#permissions)
- [Using Hum](#using-hum)
- [Where Hum keeps things](#where-hum-keeps-things)
- [Uninstall](#uninstall)

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask millerroberts180/line-apps/hum
```

Or download `Hum-1.0.0.dmg` from [Hum’s page](https://lineapps.vercel.app/hum/),
open it, and drag **Hum** onto the **Applications** shortcut beside it. Then
eject the disk image. On Apple silicon, the
[Line Apps](https://lineapps.vercel.app) installer puts in Hum with Tuck,
Pulse, and Glow.

1. Open Hum from Applications. Hum isn’t notarized yet, so the first time,
   macOS stops it: choose **Done**, then open System Settings › Privacy &
   Security and choose **Open Anyway** beside Hum. After that it opens
   normally.
2. Hum lives in the menu bar, as Hum’s mark. It shows a Dock icon only while
   the Listening History window is open. The player appears right away and
   shows the song once Music or Spotify is playing.
3. The first time you use a control for Music or for Spotify, macOS asks
   whether Hum may control that app. Choose **Allow**. It asks once per app;
   see [Permissions](#permissions).
4. To start Hum when you log in, turn on **Open at login** in Settings ›
   General. If macOS wants your approval, Settings says “Waiting for approval”:
   choose **Open Login Items…** and turn Hum on in System Settings › General ›
   Login Items.
5. To add a widget, choose Edit Widgets from the desktop’s shortcut menu or at
   the bottom of Notification Center, and look for Hum.

A release that `scripts/release.sh` signs with a Developer ID and has
notarized opens without the Open Anyway step; see
[Release](development.md#release).

## Music, Spotify, and the demo

Hum controls Spotify only through the Spotify app: its AppleScript interface
and the notifications it posts. Hum has no Spotify sign-in, uses no Spotify Web
API, and never plays Spotify audio itself. Music works the same way, through
Music’s own scripting. The demo is Hum’s built-in stand-in, for screenshots and
for trying Hum without either app.

| | Spotify | Music | Demo |
| --- | --- | --- | --- |
| Now: the song, artwork, transport, seek, volume, shuffle | Yes | Yes | Yes |
| Repeat | Off, all and one | Off, all and one | Off, all and one |
| Copy Link · Show in App | Yes | Yes | No |
| Save (Favorite) | No: Spotify’s app doesn’t let other apps save | Yes | Yes |
| Devices | No | AirPlay | Yes |
| History and Listening History, including import and export | Yes | Yes | Yes |
| Playing a song from History or Listening History | Yes, one song at a time | Yes | Yes |

Spotify’s app doesn’t let other apps choose repeat one, so Hum makes its own:
with One, Hum keeps Spotify’s repeat on and starts the song over just before it
ends, and each time through counts as a play in History. Spotify’s own window
shows its repeat on, not repeat one; the first time you choose One, a note on
the repeat button says so. Turning repeat off in Spotify ends One, and One
isn’t kept when Hum quits: it comes back as All. Shuffle and repeat
changed in either app show on the player within about a second while that app
is in front, and when you point at the player.

The player, its menus, the menu-bar item, and the widgets never name the app
that’s playing. Status, Settings › Sources, and the Listening History window
do, where it helps to know.

## Permissions

Hum controls Music and Spotify with Apple Events, so macOS asks once per app
for Automation permission. It never asks at launch. Song names and play state
arrive through notifications that need no permission, and the prompt appears
only the first time you use a control, or when you click **Allow…** on Status.

Status lists each app as Allowed, Not allowed, Not asked yet, Not open, or Not
installed. macOS reports an app’s permission only while that app is open, and
Hum never opens an app just to ask. For an app that’s Not allowed,
**Open System Settings…** opens Privacy & Security › Automation, where you can
turn it on under Hum.

Hum never launches a music app on its own: only something you choose, such as
Play or Show in App, does that.

## Using Hum

Hum lives in the menu bar. Its player is a small floating window of album art;
point at it and the controls appear, and they go the moment the pointer leaves,
unless you’re dragging the seek bar or a popover is open. While the Listening
History window is open, Hum also has a Dock icon and its own menu bar. **Hum Help**,
in its Help menu, opens this section as a page in your browser.

### Surfaces

The player has three surfaces: **Now**, **History**, and **Status**. Swipe
sideways with two fingers, press ⌘1 – ⌘3, or choose from Show ▸ to move between
them. The page indicator along the top appears only when the page changes, to
show where you are, and fades a moment after the page settles. Right-click the player for its menu: the song’s actions, Style ▸, Pin to ▸,
Show ▸ (Now, History, Status), Move to Menu Bar, and Hide Player.

### Styles

Choose a style in Settings › Appearance, or from Style ▸ in the player’s menu.
Each style keeps a light look and a dark look, and Reset Style puts back the
original. In every style the song’s title is a step larger than the artist
line, so it stands apart.

- **Art Only**: the cover alone at rest, with an optional progress line or
  ring. Point at it and everything appears over the cover: the title and
  artist, Favorite and More, the seek bar, shuffle, previous, play, next and
  repeat, and at the larger sizes the volume and the devices.
- **Title**: a short bar with a small cover, the title, and the artist. Point
  at it and the controls and seek bar take the place of the words.
- **Text**: a capsule with the title and artist in words alone. Point at it
  and the five controls spread across it. Album tint fills it with the cover’s
  color.
- **Strip**: a slim bar with the cover, a seek notch, and the controls, always
  showing. Point at it and the notch grows and shows the time.
- **Wide**: a card with the cover at its leading edge and, beside it, the
  title and artist with Favorite and More, a seek bar with times, the
  controls, and the volume, always showing. Point at it and the seek bar
  grows.
- **Big Art**: a taller card with the cover on top and, under it, the same
  title row, seek bar, controls, and volume as Wide, always showing. Point at
  it and the seek bar grows.
- **Menu Bar**: no window at all. The menu bar shows the cover, the title,
  play or pause, and next. Click it for a Now Playing popover with a larger
  cover, the seek bar, and the controls; Esc or a click outside closes it.
  **Pop Out Player**, in the popover or the menu, brings the window back in
  the style you had before.

Choose **Move to Menu Bar** in the player’s menu to switch to Menu Bar. In
Title, Text, Strip and Wide, History and Status open in a larger square that
goes back to the bar or card when you return to Now.

### Placing the player

- The player can sit in nine places on a display: Top Left, Top, Top Right,
  Left, Center, Right, Bottom Left, Bottom, and Bottom Right. Choose one from
  Pin to ▸ in the player’s menu, or with Position in Settings › Behavior.
- Throw the player, or drag it and let go, and it settles in the nearest of
  the nine places, on any display. Turn this off with **Snap when thrown** in
  Settings › Behavior.
- With Snap when thrown off, drag the player anywhere you like: it stays
  exactly where you drop it.
- A pinned player keeps its place when it changes size, and each display
  remembers its own place and size.
- Show the player in Settings › Behavior chooses when it appears: Always, On
  Track Change, Under Menu Bar, or On Request.

### The menu-bar menu

Hum’s mark sits in the menu bar, dimmed when no music app is available. Click
it for the song playing (its title, then its artist, shortened with “…” when
they’re long, so the menu stays narrow) or Nothing Playing, Play or Pause,
Next Track, Previous Track, Show Player or Hide Player (with your shortcut, if
you set one), Listening History…, Settings…, and Quit Hum. In the Menu Bar
style the item is the player itself: click it for the popover, and right-click
it for this menu, with Pop Out Player in place of Show Player.

With Line Apps (the bundle’s short line in the menu bar), a click on the line
collapses Hum’s item into it, with Tuck’s, Pulse’s and Glow’s, and another
brings them all back where they were. The player window stays as it is. While
collapsed, Hum in the line’s right-click menu, or opening Hum again, shows the
player; in the Menu Bar style, whose popover has nowhere to hang from, it opens
Settings. Quitting Line Apps brings the item back.

### Widgets

Add a Hum widget from the widget gallery: choose Edit Widgets from the
desktop’s shortcut menu, or at the bottom of Notification Center, and look for
Hum. There are three:

- **Art Only**: small, or large with the title, progress, and controls over
  the cover.
- **Title**: medium, with the cover beside the title, controls, and progress.
- **Text**: small, with the title and artist.

Small widgets have no buttons: click one to show the player. Medium and large
widgets have controls, which work without bringing Hum forward. With nothing
playing a widget shows Hum’s mark, and when Hum isn’t running it shows the
last song, paused. If the widgets ever stop updating after Hum is updated,
quitting and opening Hum again sets them going.

### Status

Status shows the app Hum follows and what it’s doing: Playing, Paused, Open,
nothing playing, Not open, or Not installed. “Chosen automatically” means Hum
picked it, because Settings › Sources is set to Automatic. With neither app on
this Mac, Status says No Music App.

Below that, Status lists Music and then Spotify, each with its own icon from
the app on this Mac (as Settings › Sources shows them), and whether Hum may
control each one:

- **Allowed**: Hum can control the app. There’s nothing to do.
- **Not allowed**: you chose Don’t Allow when macOS asked. Click
  **Open System Settings…**, then turn the app on under Hum in Privacy &
  Security › Automation.
- **Not asked yet**: click **Allow…** and choose Allow when macOS asks.
- **Not open**: macOS reports an app’s permission only while the app is open,
  and Hum never opens an app just to ask. Open the app to see where it stands.
- **Not installed**: the app isn’t on this Mac, so its row is dimmed.

Status checks again each time it appears and each time you come back to Hum.
**Settings…** at the bottom opens Settings › Sources, where Control picks
Automatic, Music, or Spotify.

### Settings

Choose Settings… from the menu-bar menu. The sidebar groups the panes: General
first; then Player, with Appearance, Behavior, and Shortcuts; then Music, with
Sources and History & Privacy; and last Hum, with Hum’s version, what it does,
and Quit Hum. About Hum, in Hum’s own menu, opens the Hum pane too. Settings
brings no Dock icon, and ⌘W closes it.

### History and Listening History

Hum notes each song you play: a play counts after 30 seconds and half the song,
or 4 minutes for long songs. History stays in a file on this Mac, and Hum never
sends it anywhere.

- History shows what stands out about the song playing and this session.
- See All in History, Listening History… in the menu-bar menu, or Open
  Listening History… in Settings › History & Privacy opens the Listening
  History window: This Week, Calendar, History, Top, and Rediscover.
- The window opens with its sidebar hidden, to leave the most room. Show it
  with the sidebar button in the toolbar, and it stays as you leave it while
  Hum runs.
- In History, the Any Artist, Any Album, Any Playlist, and Any Time menus
  narrow the list, and Clear Filters puts it back. Any Playlist appears only
  once a listen came from a playlist.
- Top ranks your songs, artists, or albums for the period you choose.
- In Calendar, click a day to see its listens, or move between days with the
  arrow keys.
- Settings › History & Privacy has **Collect listening history**, to turn
  collection off and on; **Import Spotify History…**, for Spotify’s data
  download, and **Remove Imported History…**, to take it out again;
  **Export as JSON…** and **Export as CSV…**; and **Erase All History…**.
  Erasing or removing listens leaves nothing of them in the file.

### Keyboard

| Keys | Action |
| --- | --- |
| Space | Play / Pause |
| ⌘→ / ⌘← | Next / Previous track |
| ⌘↑ / ⌘↓ | Volume up / down |
| ⌥⇧B | Favorite the current track, in Music; a short note confirms it |
| ⌘1 – ⌘3 | Now, History, Status |
| ← / → | Previous / next surface, when the player has focus and no text field is active |
| ⌘, | Settings |
| Esc | Back out one level: close the topmost popover or menu, or the Menu Bar popover; in Title, Text, Strip or Wide, go back to Now from History or Status |
| ⌘W | Hide Player; in Settings or the Listening History window, close that window |
| None until you set one | Show or hide the player from anywhere; in Menu Bar, open or close its popover (global; set it in Settings › Shortcuts, and the menu-bar menu shows it) |
| ↑ ↓ ↩ | Navigate and choose in lists (History, the Listening History window) |

### Pointer and trackpad

- Swipe two fingers sideways to move between surfaces.
- Swipe two fingers up or down on the cover, or scroll over the volume slider,
  to change the volume.
- Pinch the player to make it larger or smaller.
- Right-click the player for its menu.

## Where Hum keeps things

Everything stays on your Mac.

| What | Where |
| --- | --- |
| Settings | `~/Library/Application Support/com.millerroberts.hum/Settings.json` |
| Listening history | `~/Library/Application Support/com.millerroberts.hum/History.sqlite` |
| Caches: artwork and thumbnails | `~/Library/Caches/com.millerroberts.hum/` (safe to delete) |
| What the widgets show: the song and its cover | `~/Library/Application Support/Hum/widget/` |
| Where the Listening History window and the menu-bar item sit | `~/Library/Preferences/com.millerroberts.hum.plist` |
| Automation permissions | System Settings › Privacy & Security › Automation |

Demo mode uses `Settings-Demo.json` and `History-Demo.sqlite` beside the real
ones, and keeps its artwork in memory. With `HUM_SUPPORT_DIR` set, settings,
history, and caches go in that folder instead.

The widget folder is the exception: it’s always
`~/Library/Application Support/Hum/widget/`, even with `HUM_SUPPORT_DIR` set,
and the demo writes there too. The widget extension runs in its own sandbox,
can’t see Hum’s environment, and may read only that one folder, which its
entitlement names (a read-only exception relative to your home folder). Hum
finds your real home folder for it, not a sandbox container’s. Sharing an App
Group instead would need a build signed by a developer team. The folder holds
`snapshot.json` (the song and its play state) and the current cover, written as
they change, and nothing else: no history, no account, and not the name of the
app that’s playing.

## Uninstall

First, if **Open at login** is on, turn it off in Settings › General, and
remove any Hum widgets from the desktop or Notification Center.

With Homebrew, `brew uninstall --cask millerroberts180/line-apps/hum` quits
Hum and removes it. Adding `--zap` removes your settings, history, caches, and
the widget folder too.

Without Homebrew:

1. Quit Hum from the menu-bar icon (**Quit Hum**), then move Hum from
   Applications to the Trash.
2. To remove your settings, history, caches, and the widget folder too:

   ```sh
   rm -rf ~/Library/"Application Support"/com.millerroberts.hum ~/Library/Caches/com.millerroberts.hum ~/Library/"Application Support"/Hum
   defaults delete com.millerroberts.hum
   ```

3. To forget the Automation permissions: `tccutil reset AppleEvents com.millerroberts.hum`.

