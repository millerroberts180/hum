# Hum Design Spec

Version 1.3 · Applies to every surface, component, and style in Hum. Version 1.1 is the 2026-11-07 redesign: Play and Find are gone, Status joins Now and Echo, new styles (with Menu Bar), nine pin positions, a lean menu-bar menu with Hum's logo, widgets, Liquid Glass on macOS 26, and Settings shown as visual choices (§13.9–§13.18). Version 1.2 is the 2026-11-08 follow-up: Glass, Data and Session are retired, leaving six styles; the song title is a step larger; the page indicator shows only when the page changes; and Spotify's own app icon shows where Hum names Spotify (§13.19–§13.22). Version 1.3 is the 2026-11-09 round: Echo is renamed History; repeat one works with Spotify; the menu is narrower and has Listening History…; Settings no longer brings the Dock icon, its About pane becomes Hum, its panes and sidebar get section headers, and its buttons take Hum's action style; hover controls leave the moment the pointer does; a new Wide style and a new Big Art, both on an outlined card; and the Listening History window gets pill menus, no Top › Playlists, no whole-calendar focus ring, and opens with its sidebar collapsed (§13.23–§13.31). The widgets, on hold for most of the round, come back at its end: Hum retires a widget extension left running from an older build, and three widgets stay, Art Only, Title and Text (§7.3, §13.32, §13.33). Last, repeat's glyph change keeps time with its color and dot, Spotify's repeat one starts over early enough to land, and shuffle and repeat changed in Spotify show on the player (§13.34). The first time One is picked for Spotify, the repeat button says once that Hum repeats the song itself (§13.35).

This document is the single source of truth for how Hum looks, moves, and behaves. When code and this spec disagree, the spec wins until it is amended. When this spec is silent, follow Apple's Human Interface Guidelines for macOS.

---

## 1. North star

**Hum should feel like Apple's own audio player, made portable.**

- The **visual language and behavior** are Apple's: the Apple Music MiniPlayer and Now Playing screen, Control Center's Now Playing module, SF Pro, SF Symbols, system materials, continuous corners, spring motion, and standard macOS conventions for menus, shortcuts, focus, and windows.
- The **playback features** are the essentials, done well: play and pause, skip, seek, shuffle and repeat (off, all, one), save, volume, a device picker where the source has one, and a right-click menu on the song. Each appears where the source supports it (§1.3).
- Everything is **rendered in Apple's visual language**. Hum never uses Spotify green, Spotify's typeface, or Spotify-style dark-only chrome, and the player, its menus and its widgets never name the music app (§10). A first-time user should assume Apple made Hum.

### The feel in one sentence per surface

| Surface | It should feel like… |
| --- | --- |
| **Now** | The Apple Music MiniPlayer: artwork is the window, controls appear when you reach for them. Each style (§7) is another shape of that idea. |
| **History** | An Apple Health or Fitness summary card for your listening: calm, factual, rounded numerals. |
| **Status** | Control Center's Wi-Fi or Bluetooth module: which music app Hum is connected to, and whether macOS lets Hum control it, at a glance. |

### 1.1 Overall feel

The emotion Hum aims for is **calm confidence**. It is always ready, never asks for attention, and responds the instant you reach for it. It should feel like a well-made instrument, with weight and precision, not like a web page in a window.

Hum serves the four needs Apple designs for:

| Need | What it means in Hum |
| --- | --- |
| **Predictability** | The same control sits in the same place and behaves the same way on every surface and in every style. Things leave the way they came. |
| **Understanding** | You can always tell what is playing, from which app, and on which device. You can tell what a control does before you press it. |
| **Achievement** | Every common action is one click or one key away: play, skip, seek, save, shuffle, repeat, move the player. |
| **Joy** | Earned through craft, never added on top. Examples: the artwork easing back as the music pauses, a page settling under your fingers, a window you can throw into a corner. |

Five qualities, each with a test you can run:

| Quality | Test |
| --- | --- |
| **Instant** | Visible response within one frame of input (16 ms; 8 ms on 120 Hz displays). Nothing on the input path waits for the music app or the network. |
| **Physical** | Everything you can touch tracks the pointer 1:1, moves on springs, carries momentum when released, and resists at boundaries. Anything in motion can be grabbed and redirected. |
| **Quiet** | Neutral chrome plus a single accent hue. At rest, nothing moves except the progress line. No UI sounds. Near-zero CPU. |
| **Deferential** | The artwork is the interface. Controls appear when you reach for them and step back when you leave. |
| **Coherent** | Things that look alike behave alike. Eight button families and two slider behaviors cover the whole app (§5.9, §5.10); there are no one-off controls. |

Hum must never feel like a web page in a frame, a dashboard, a skin over someone else's app, or a toy.

### 1.2 Feel in numbers

| Measure | Target |
| --- | --- |
| Input to visible feedback | ≤ 1 frame |
| Controls reveal on hover | 180 ms, opacity only |
| Controls hide after the pointer leaves | At once: the 180-ms conceal starts the moment the pointer leaves the window (§13.28) |
| Spring for interactive motion | response 0.3–0.4 s, damping 1.0 (no overshoot); 0.85 only after a flick. *(`Motion.artworkPause`, the padded cover's settle, retired with Glass, Data and Session, §13.19.)* |
| Longest animation | 0.45 s (palette color change on a new track). No spatial animation uses a response above 0.4 s. |
| Spinner delay | 400 ms, so fast loads show nothing |
| Idle CPU while paused | ≈ 0% |
| Frame pacing | Display-linked: 120 Hz on ProMotion displays, no dropped frames while paging, resizing, or throwing the window |

### 1.3 How Hum reaches each source

Hum controls Spotify only through the Spotify app: its AppleScript interface and the notifications it posts. Hum has no Spotify sign-in, uses no Spotify Web API, and never plays Spotify audio itself. *Decided 2026-11-06.*

| | Spotify | Music | Demo |
| --- | --- | --- | --- |
| Now: the song, artwork, transport, seek, volume, shuffle | Yes | Yes | Yes |
| Repeat | Off, all and one. One is Hum's: Spotify's app has only on and off, so Hum keeps Spotify's repeat on and starts the song again as it ends (§5.2, §13.24) | Off, all and one | Off, all and one |
| Copy Link · Show in App | Yes | Yes | No |
| Save (Favorite) | No: Spotify's app doesn't let other apps save | Yes | Yes |
| Devices (§5.8) | No | AirPlay | Yes |
| The History page and the Listening History window, including import and export | Yes | Yes | Yes |
| Playing a song from the History page or the Listening History window | Yes, one song at a time | Yes | Yes |

With `--demo-attribution Spotify`, the demo follows the Spotify column for Save, repeat and devices, and names no album or playlist a song plays from (§6.5), so its screenshots show what a Spotify listener sees. Hum's own library and search (Play and Find) were removed on 2026-11-07, for every source (§13.9).

---

## 2. Design principles

These are ranked. When two conflict, the higher one wins.

1. **Music first, chrome last.** Album art and the current track are the content. Every pixel of UI must justify itself against covering the art. At rest, the Now surface shows artwork and nothing else, unless the listener turns on a resting progress line or ring (§5.2).
2. **Native before novel.** Use the system control, symbol, font, material, menu, or gesture before inventing one. Break a macOS convention only when the improvement is provable, and write the reason into this spec.
3. **Instant response.** Feedback starts on mouse-down or key-down, never on release. Transport commands update the UI optimistically and reconcile when the music app confirms. Nothing on the input path waits on a network call.
4. **Continuous, interruptible motion.** Everything the user can touch moves with springs that start from the current on-screen value and carry the user's velocity. No animation ever blocks input.
5. **Progressive disclosure.** Cover first, then controls, then insights, then status. Each step is one deliberate action away, and none of them appear uninvited.
6. **One home per feature.** Every action has exactly one canonical place, plus the standard alternates of right-click menu, keyboard shortcut, and menu bar menu. Settings hold preferences, never essential behavior.
7. **Calm by default.** No badges, nags, streaks, confetti, glow, or animated gradients. Motion explains a change of state, and nothing else moves.
8. **Accessible from the first build.** VoiceOver, full keyboard control, Reduce Motion, Reduce Transparency, Increase Contrast, and larger text are part of every component's definition of done, not a later pass.
9. **Quiet on the machine.** Near-zero CPU while idle. No timers while paused or hidden. Animations stop when the window is occluded.

---

## 3. Foundations (design tokens)

All values are expressed as tokens in `Sources/HumUI/Design/`. Components never hard-code a number that a token covers. Token enums: `Spacing`, `Radius`, `Motion`, `HumType`, `HumColor`, `HumMaterial` (wrapping `HumGlass`), `HumIcon`, `PlayerMetrics`.

### 3.1 Layout grid and spacing

A 4-pt base grid. All padding, gaps, and sizes are multiples of 4, with 2 allowed only for hairline insets. The only other exceptions are system metrics Hum matches on purpose, each named where it is used (the style tiles in §8).

| Token | Value | Typical use |
| --- | --- | --- |
| `Spacing.xxs` | 2 | Hairline insets, badge padding |
| `Spacing.xs` | 4 | Icon-to-label gap inside a control |
| `Spacing.s` | 8 | Between related controls; list row vertical padding |
| `Spacing.m` | 12 | Card inner padding (small); section gap in compact layouts |
| `Spacing.l` | 16 | Card inner padding (default); window content inset |
| `Spacing.xl` | 24 | Between sections; large-size window inset |
| `Spacing.xxl` | 32 | History expanded view section breaks |

Rules:
- Spacing communicates grouping. Related items get `s`; groups get `m`–`l`; sections get `xl`.
- Insets scale with player size class (§6.1). Never place content closer than `s` to the window edge.

### 3.2 Shape

- All rounded rectangles use **continuous corners** (`RoundedRectangle(cornerRadius:style: .continuous)`).
- **Concentricity:** a shape inside another uses `inner radius = outer radius − inset`. This applies to artwork inside a padded card, buttons inside a capsule, and so on.

| Token | Value | Use |
| --- | --- | --- |
| `Radius.panel(side:)` | macOS 15: 10. macOS 26: `clamp(12, side × 0.075, 26)`, rounded to whole points | Player window corners: the system window radius on macOS 15; on macOS 26 it scales with size |
| `Radius.card` | 12 | Cards, popovers, Strip's window |
| `Radius.control` | 8 | Buttons with a backing, text fields, chips (chips may be capsules) |
| `Radius.artSmall` | 4 | Artwork ≤ 40 pt (list rows) |
| `Radius.artMedium` | 6 | Artwork 41–120 pt (cards, Title's cover) |
| Circle | — | Artists are always circular, as in Apple Music |
| Capsule | — | Sliders, chips, the HUD, segmented page indicator, Text's window |

### 3.3 Typography

**Typeface:** SF Pro via the system font only. Use **SF Pro Rounded** only for History numerals and stat values (`.fontDesign(.rounded)`), as Apple's Fitness and Health summaries do. Use SF Mono nowhere. Custom fonts are not allowed in v1.

Use macOS text styles so Dynamic Type and accessibility sizes work. Here is the mapping for Hum's roles:

| Role (`HumType`) | macOS style | Weight | Notes |
| --- | --- | --- | --- |
| `trackTitle` | `.title3` (15) at S/M; `.title2` (17) at L | Semibold | One line; marquee on hover if truncated (§5.4). *Amended 2026-11-08 (§13.20): a step larger, so the title stands apart from the artist line.* |
| `trackArtist` | `.subheadline` (11) at S; `.body` (13) at M/L | Regular | Secondary color |
| `trackAlbum` | `.subheadline` | Regular | Tertiary color; shares the artist's line as "Artist — Album": at L in the square styles, at M and L in Big Art (§6.1, §7). *Amended 2026-11-07 to match §7.* |
| `time` | `.callout` (12) at M and L; `.caption` (10) at S | Regular | `.monospacedDigit()`, tertiary; shows remaining time as "−1:23" |
| `sectionHeader` | `.headline` (13) | Bold | Section headers in History, Status, and the History window |
| `rowTitle` | `.body` (13) | Regular | List rows; the playing row is marked by the accent `waveform` glyph, and its title stays `label` |
| `rowSubtitle` | `.subheadline` (11) | Regular | Secondary |
| `cardTitle` | `.callout` (12) | Semibold | Under cards, max 2 lines |
| `textTitle` | `.headline` (13) | Semibold | Text style's title, in `label` (or the palette `primary` with album tint). *Amended 2026-11-08 (§13.20): a step larger.* |
| `textArtist` | `.subheadline` (11) | Regular | Text style's artist, in `secondaryLabel` (or the palette `secondary` with album tint) |
| `statValue` | `.title` (22) at M; `.largeTitle` (26) at L | Semibold, rounded | History numbers |
| `statLabel` | `.caption` | Medium | History labels, uppercase not allowed (sentence case) |
| `caption` | `.caption` | Regular | Captions and footnotes under content (History's filter caption, History's "tracked by Hum" line) |
| `badge` | `.caption2` (10) | Bold | "E" explicit badge |

Rules:
- Hierarchy is built from **weight and color**, then size. Only two text sizes are allowed per surface region.
- Over artwork or translucent material, step text up one weight and use vibrant label colors (§3.5).
- Never use all caps. **Title Case** for buttons, menu items, section headers, empty-state titles, and window and pane titles, as in Music and the macOS HIG ("Show in App", "Listening History", "Nothing Playing"). **Sentence case** for Settings control labels, as in System Settings ("Snap when thrown"), and for descriptions, captions, banners, and insight sentences.
- Truncate with a tail ellipsis by default. Titles may marquee (§5.4), but artist names never do.
- **Never set `.tracking` by hand.** SF Pro's optical sizes and built-in tracking already tighten large text and open up small text; manual tracking fights them. For legibility over artwork or materials, add weight instead (one step heavier).
- Use `.monospacedDigit()` for any number that changes in place: times, counts, and volume.

### 3.4 Iconography

**SF Symbols only**, except Hum's own mark in the menu bar (§5.8). Use the hierarchical rendering mode by default, with the symbol weight matched to adjacent text. Symbols sit on the text baseline when paired with text.

| Action | Symbol | Notes |
| --- | --- | --- |
| Play / Pause | `play.fill` / `pause.fill` | Morph with `.contentTransition(.symbolEffect(.replace))` |
| Next / Previous | `forward.fill` / `backward.fill` | Press: `.symbolEffect(.bounce)` in the travel direction |
| Shuffle | `shuffle` | Active state: see §5.2 |
| Repeat | `repeat` / `repeat.1` | Three states: off, all, one. The glyph change cross-fades with the toggle's color and dot, not the symbol's replace effect (§5.2) |
| Save (Apple Music) | `star` / `star.fill` | Matches Apple Music's "Favorite" |
| Devices | `hifispeaker.2` (picker), `airplayaudio` (AirPlay in Music) | Music's AirPlay devices, and the demo's |
| Volume | `speaker.fill` / `speaker.wave.1.fill` / `speaker.wave.2.fill` / `speaker.wave.3.fill` / `speaker.slash.fill` | Variable by level |
| More | `ellipsis` | Opens the same menu as right-click |
| Pin to | `rectangle.inset.topleft.filled` and its siblings for each position | The Pin to ▸ menu on macOS 26, where menus show symbols |
| Move to Menu Bar / Pop Out Player | `menubar.arrow.up.rectangle` / `menubar.arrow.down.rectangle` | |
| Hum (menu bar) | Hum's Vibrato mark, not an SF Symbol | A template image drawn from `design/logo/hum-symbol-small.svg` (§5.8) |
| Now playing marker | `waveform` | Animated with `.symbolEffect(.variableColor.iterative)` only while playing; static when paused or with Reduce Motion |
| Explicit | `e.square.fill` | At the row-subtitle size, `secondaryLabel`; VoiceOver "Explicit" |
| Missing artwork | `music.note` (lists: `music.mic` for podcasts, `music.note.list` for playlists) | Centered at 0.55 of the tile's side, `.regular`, `quaternaryLabel`, on a flat `fillTertiary` tile (no gradient) |
| Surfaces | Now `play.circle` · History `waveform.path` · Status `antenna.radiowaves.left.and.right` | Page indicator tooltips and menus |

Glyph sizes, backings, and hit targets are defined in §3.8.

### 3.5 Color language

**The music brings the color.** Hum's own chrome is neutral: system grays, white over artwork, and system materials. Color enters in exactly three ways, and each one carries a single meaning:

| Layer | Meaning | Where it shows |
| --- | --- | --- |
| **Artwork** | *What* is playing | The art itself, the art backdrop, and the artwork palette (§3.5.4) |
| **Accent** | *State*: on, selected, playing, focused | The exhaustive list in §3.5.3 |
| **Status** | *Problems* | Red and orange glyphs (§3.5.6) |

If a color does not come from one of these three layers, it does not belong in Hum. Components reference `HumColor` roles, never raw color values.

#### 3.5.1 Color contexts

Every component renders in one of two contexts, read from an environment value (`\.humColorContext`). A component asks for a role such as `HumColor.secondaryLabel`, and the context resolves it:

- **`.material`**: on system materials or window backgrounds. Follows light and dark appearance through system dynamic colors.
- **`.artwork`**: over artwork with the controls scrim. Always a dark context, because the scrim guarantees a dark base. Dark text never sits on artwork.

#### 3.5.2 Neutral roles

| Role (`HumColor`) | `.material` | `.artwork` | Use |
| --- | --- | --- | --- |
| `label` | `labelColor` | white 100% | Titles, primary glyphs, the play/pause glyph |
| `secondaryLabel` | `secondaryLabelColor` | white 72% | Artist, secondary and inactive glyphs, slider fill at rest |
| `tertiaryLabel` | `tertiaryLabelColor` | white 50% | Times, album, captions |
| `quaternaryLabel` | `quaternaryLabelColor` | white 30% | Placeholder glyphs, temporarily unavailable controls |
| `trackFill` | `tertiarySystemFill` | white 24% | Unfilled part of sliders |
| `fillQuaternary` | `quaternarySystemFill` | white 12% | Hover backings, chips at rest, artwork placeholders |
| `fillTertiary` | `tertiarySystemFill` | white 20% | Pressed backings |
| `separator` | `separatorColor` | white 14% | Hairlines in lists only |
| `glassStroke` | black 8% (light) / white 18% (dark) | white 18% | 1-pt inner edge of glass on macOS 15 (content cards take a fill, §3.6) |
| `shadow` | black, at the opacities in §3.6 | same | Elevation only |

#### 3.5.3 Accent

**Accent modes**, chosen by the user and stored per appearance:
1. **System** (default): `NSColor.controlAccentColor`, which follows the user's macOS accent. When the user picks the Graphite accent, Hum's accent becomes gray, and active toggles stay recognizable through their dot.
2. **Album:** the `accent` field of the current artwork palette (§3.5.4).
3. **Custom:** a color the user picks, contrast-adjusted the same way as Album.

**The accent appears only in these places:**
- an active toggle's glyph and its 4-pt dot
- the playing row's `waveform` marker
- the filled Save glyph
- the active device in `DeviceRow` and `DevicePicker`
- the floating play button on cards
- the prominent text button (at most one per view)
- History data marks
- the focus ring and text selection, which the system draws

**The accent never appears on** seek or volume fills, titles, artist names, backgrounds, large fills, or resting borders. Using it only for state is what keeps it meaningful.

**Contrast:**
- Each context gets its own adjusted accent variant. Over artwork, and on dark material, raise its lightness until it reaches 3:1 against black (in practice OKLCH L ≥ 0.72). On light material, lower it until it reaches 3:1 against the window background. Accent text needs 4.5:1.
- Content on an accent fill (the card play button, the prominent button) is white when the accent's OKLCH L is below 0.70, and black otherwise.

#### 3.5.4 Artwork palette

The palette follows Apple Music's artwork color model: each artwork yields one background color and a ranked set of text colors guaranteed to be legible on it.

| Field (`ArtworkPalette`) | Derived from | Used for |
| --- | --- | --- |
| `background` | Dominant color of the outer 15% border of the image | Backdrop tint under Reduce Transparency, the album-tinted Text background, the placeholder while the next artwork loads |
| `primary` | Most common color that contrasts with `background`, adjusted to ≥ 4.5:1 | Title in tinted contexts |
| `secondary` | Next distinct color, adjusted to ≥ 4.5:1 | Artist in tinted contexts |
| `tertiary` | `primary` at 60% | Times and labels in tinted contexts |
| `accent` | The most saturated color covering ≥ 5% of the image with OKLCH chroma ≥ 0.08 | Album accent mode |
| `isDark` | `background` OKLCH L < 0.6 | Chooses light-on-dark or dark-on-light controls in tinted contexts |

Extraction rules:
- Downsample to 40 × 40 off the main thread, convert to OKLab, and cluster with k-means (k = 6, fixed seed, so the same art always gives the same palette).
- Adjust contrast by stepping OKLCH lightness away from `background` in steps of 0.02, keeping hue and chroma.
- If no candidate reaches the bar, use white or black at 85%.
- For grayscale art (chroma < 0.03 everywhere), `accent` is nil and Album mode falls back to System.
- Cache the palette alongside the artwork in the artwork cache (memory and disk). Never compute it per frame or during an animation.

#### 3.5.5 Color in motion

- On a track change, every palette-driven color (backdrop tint, album accent, tinted text) interpolates in OKLCH along the shorter hue arc over 0.45 s ease-in-out (`Motion.color`), starting with the artwork crossfade. Colors never snap.
- Reduce Motion keeps color transitions, because they are not spatial, but shortens them to 0.2 s.
- Hum adds no animation of its own to light/dark appearance changes; the system handles them.

#### 3.5.6 Status colors

| Role | Color | Use |
| --- | --- | --- |
| `critical` | `systemRed` | Errors that block playback; destructive actions such as "Erase All History" |
| `warning` | `systemOrange` | Degraded states such as "Your music app isn’t responding", and missing Automation access |

- A status color applies to the glyph, plus at most a 10% tint on the banner background. The text stays neutral.
- Hum's chrome uses no green and no yellow. Green would read as Spotify branding, and success already shows in the outcome itself (for example, the Save glyph fills).

#### 3.5.7 Brand and source color

- Never Spotify green. The player, its menus and its widgets don't identify the source at all (§10); the Status page does (§6.3). Hum never recolors its UI for a source.
- Where Hum shows the music apps (the Status page, Settings › Sources), Spotify has its own icon, as Music does: Spotify.app's icon, read from the installed app's bundle through `NSWorkspace`, the way macOS shows apps. Hum never redraws, recolors, crops, badges or bundles it, and never shows it on the player, its menus or the widgets (§10). If Spotify isn't installed, the system's generic application icon stands in. The History window names Spotify in text. *Decided 2026-11-08 (§13.22).*
- Hum has no brand color inside the UI. The app icon may carry one.

#### 3.5.8 Data color (History)

- Data uses one hue: the current accent. Sequential scales (such as `HeatCalendar`) have five steps: `fillQuaternary` for zero, then the accent at 25, 50, 75, and 100%.
- Comparisons use the accent against `tertiaryLabel`. No second hue, no rainbow palettes, no gradients.
- Every value also appears as text. Color never carries a value on its own.

#### 3.5.9 Color accessibility

- **Never encode meaning in color alone.** Active toggles also get a dot, the playing row also gets the `waveform` glyph, and errors also get a glyph and words.
- **Differentiate Without Color:** nothing extra is needed. An active toggle always has its dot, and the playing row always has its `waveform` glyph.
- **Increase Contrast:** over artwork, label whites become 100 / 90 / 72%, the scrim deepens to 75%, hover fills double in opacity, and `glassStroke` uses full `separatorColor`. Off artwork, `secondaryLabel` text steps up to `label` and `tertiaryLabel` text to `secondaryLabel`.
- **Minimum contrast:** 4.5:1 for body text; 3:1 for large text, glyphs, and focus indicators. These apply in every accent mode and every context. `tertiaryLabel` is for short captions and times, as in Apple's players, never for a sentence the listener has to read; under Increase Contrast it meets 4.5:1 too.

### 3.6 Materials and depth

Hum follows Apple's layering: content (artwork) at the bottom, a translucent functional layer for controls above it, and nothing stacked beyond two layers. *Amended 2026-11-07 by the redesign (§13.9–§13.18).*

| Material (`HumMaterial`) | macOS 15, and Frosted on macOS 26 | macOS 26 with Liquid Glass (§3.6.1) | Use |
| --- | --- | --- | --- |
| `controlsScrim` | Bottom-up gradient over the artwork: black 0% → 55% across the lower 45% of the cover, or the controls' height plus 32 pt where that is taller, with a feather above it of 16% of the side (at least 32 pt). The art under it stays sharp: no blur, as in Apple's MiniPlayer | Replaced by `controlsPlatter` | Art Only's hover controls |
| `controlsPlatter` | — (the scrim is used) | Liquid Glass `.clear`, a rounded rectangle concentric with the window, inset `Spacing.s` from its sides and bottom and as tall as the controls plus `Spacing.m`, over a dimming layer of the same shape (black 35%), as Apple asks for clear glass over media | Art Only's hover controls |
| `glassCard` | `NSVisualEffectView` `.hudWindow`, `.withinWindow`, active | `glassEffect(.regular)` | Title's and Strip's windows; the HUD |
| `glassCapsule` | `.popover`, behind the window, in a capsule | `glassEffect(.regular, in: .capsule)` | Text's window |
| `popover` | `.popover` material | System popover (Liquid Glass) | Device picker, the Menu Bar popover, menus |
| `sidebar` | `.sidebar` | System default | Settings sidebar, the History window |
| `artBackdrop` | Current artwork, blur radius 60, saturation 1.6, then black overlay 25% (dark) / white overlay 35% (light) | Same | Under Big Art's controls, and behind History and Status (§6.3, §6.5) |
| `windowWash` | `windowBackgroundColor` at 65% over `artBackdrop` | Same | Behind History and Status, so text on their fills keeps 4.5:1 over any cover |
| `ArtworkDim.row` | Black 45% over the artwork | Same | A row's art under its hover play glyph or playing marker |
| `ArtworkDim.card` | Black 12% over the artwork | Same | A card's art while it's hovered |

Rules:
- **Never place a light translucent layer on another translucent layer.** Glass sits on art or on the desktop, never on glass.
- **On macOS 26 nothing is drawn over Liquid Glass**: no stroke, no highlight. The system draws the edge and adapts it to what's behind, including under Increase Contrast.
- **On macOS 15** a material gets a 1-pt inner stroke (`glassStroke`) and nothing else: no gloss or highlight.
- **Glass is for what floats over content**: the HUD, the page indicator, banners over artwork, popovers, the hover controls. Content inside a surface (History's and Status's cards, an empty-state card) takes a fill (`fillQuaternary`), never glass.
- **A style whose whole window is the material** (Title, Text, Strip) is glass at the window level on macOS 26, so nothing inside it is glass again.
- Every cover gets the same treatment, whichever app it comes from (§13.17).
- Shadows communicate elevation:
  - The player window uses the system window shadow. In dark appearance it also takes the system's hairline rim: 1 px, white at 10%, inside its corner radius. None in light appearance.
  - Glyphs over artwork (transport, toggles, the resting indicator) take a soft legibility shadow, `y 0.5, blur 3, black 30%` (`HumShadow.glyphOnArt`), as in Apple's MiniPlayer. Not inside a `controlsPlatter`, whose dimming already carries them.
  - The floating card play button uses `y 2, blur 6, black 25%` (`HumShadow.cardPlay`).
  - List artwork uses `y 1, blur 2, black 15%`.
  - Cards use none; they are separated by material.
- **Reduce Transparency:** every material becomes an opaque `windowBackgroundColor`-based fill, the art backdrop becomes the album accent at 20% over the window background, and the scrim and the platter become a solid 70% black band.
- **Increase Contrast:** strokes go to 1 pt at 100% `separatorColor`, and secondary text goes to `labelColor`.

#### 3.6.1 Liquid Glass

- Hum uses Liquid Glass only on macOS 26 and later, through the public `glassEffect` API, and only while Settings › Appearance › Material is **Liquid Glass**, the default there. The other choice, **Frosted**, keeps the macOS 15 forms in the table above.
- **On macOS 15 there is no Liquid Glass and no choice:** the Material row isn't shown, and every material uses its macOS 15 form. Hum never imitates Liquid Glass there with drawn gloss, highlights, refraction, or a fake edge (§13.18).
- With Liquid Glass, Art Only's hover controls sit in the `controlsPlatter`, and Title, Text and Strip are glass at the window level. Their transport glyphs stay bare (family 1), never glass buttons on glass.
- System surfaces (menus, popovers, the Settings sidebar, the Menu Bar popover, widgets) take whatever the system draws, on either setting.

### 3.7 Motion

Springs for anything interactive; short ease-outs only for opacity-only reveals. All values live in `Motion`.

| Token | Spec | Use |
| --- | --- | --- |
| `Motion.press` | ease-out 0.10 s on mouse-down. Release springs back with `Motion.snappy`. The pressed look holds for at least 80 ms, so even a quick click shows. The scale amount depends on the button family (§5.9). | Every button press |
| `Motion.materialize` | spring response 0.30, damping 1.0. Scale 0.96 → 1.0, opacity 0 → 1, blur 6 → 0. Exit reverses along the same path, toward the same anchor. | Popovers, the HUD, the window appearing, and the window going into or out of the menu bar (§7.1) |
| `Motion.throw` | spring response 0.40, damping 1.0. Carries the release velocity; the target comes from momentum projection (deceleration 0.998). | Window throw-to-snap (§4.5) |
| `Motion.color` | ease-in-out 0.45 s, interpolated in OKLCH | Palette color changes (§3.5.5) |
| `Motion.reveal` | ease-out 0.18 s, opacity 0→1 + 8-pt upward travel | Hover controls appearing |
| `Motion.conceal` | ease-out 0.18 s, opacity 1→0 + 8-pt downward travel (opacity only under Reduce Motion); no grace period | Hover controls leaving, starting the moment the pointer exits. If the pointer comes back mid-conceal, the reveal picks up from where the conceal is (§13.28) |
| `Motion.snappy` | spring response 0.25, damping 1.0 | Hover backings, toggles, chips |
| `Motion.smooth` | spring response 0.35, damping 1.0 | Layout changes, row insert or remove, popover open |
| `Motion.pageDirect` | spring response 0.32, damping 1.0 | Surface change from click or key |
| `Motion.pageMomentum` | spring response 0.40, damping 0.85, inherits release velocity | Surface change after a swipe |
| `Motion.trackChange` | artwork crossfade 0.30 s with scale 1.02 → 1.0; text slides 6 pt + fades, 0.22 s | New track |
| `Motion.crossfade` | ease-out 0.20 s | Reduce Motion replacement for every spatial animation |

Rules:
- **Start from the presentation value.** An interrupted animation retargets from where the element is on screen, never from its logical value.
- **Spatial consistency:**
  - Next track: the new title enters from the trailing edge. Previous: from the leading edge.
  - A popover grows from its trigger.
  - Surfaces are laid out left to right as Now → History → Status, and travel matches that order.
- **Bounce only after momentum.** A spring may overshoot only when a user flick preceded it, as with `pageMomentum`.
- **Reduce Motion:** every spatial or scale animation becomes `Motion.crossfade`, artwork never scales, the `waveform` marker is static, and marquee text does not scroll.
- **Nothing loops while paused.** The only animations allowed while playing are the progress line and the waveform marker.

### 3.8 Control sizing and hit targets

Every control has three sizes:
- the **glyph** (SF Symbol point size)
- the **backing**: the circle or capsule shown on hover, press, or active
- the **hit target**: invisible, always at least as large as the backing

Rules:
- **Minimum hit target is 28 × 28 pt**, the default macOS control size. Only the S size class may go down to 24 pt, and only for tertiary controls.
- Hit targets extend 4 pt beyond the backing on each side, but never overlap a neighbor. Where they would, split the space at the midpoint.
- **Press hysteresis:** a press survives the pointer drifting up to 10 pt outside the hit target. Beyond that it cancels, and it re-arms if the pointer comes back before release.
- **Optical centering:** inside a circle, shift `play.fill` toward the trailing edge by 6% of the glyph's width so the triangle looks centered. `pause.fill` and the skip glyphs are not shifted.
- Sizes change by size class, never continuously while the window resizes, so glyphs don't shimmer during a resize. Positions follow the layout smoothly.

**Transport** (glyph / backing / hit target, in pt):

| Control | S | M | L |
| --- | --- | --- | --- |
| Play/pause | 18 / 32 / 36 | 22 / 40 / 44 | 28 / 52 / 56 |
| Previous / next | 14 / 28 / 32 | 16 / 32 / 36 | 20 / 40 / 44 |
| Shuffle, repeat, save, more | 12 / 24 / 28 | 13 / 28 / 32 | 15 / 32 / 36 |
| Gap between transport hit targets | 4 | 8 | 12 |

**Other controls:**

| Control | Size |
| --- | --- |
| Icon button (more, devices, clear, remove, pop out) | glyph 13, backing 24 circle, hit 28 |
| Floating card play button | 28 filled circle with 12 glyph (S, M); 32 with 14 (L); hit 32 / 36 (the History page and the History window, where they show cards) |
| Row hover play | 12-pt glyph over the row artwork (the History page and the History window) |
| Chip | capsule 24 tall (M) or 28 (L); horizontal padding 10 / 12; `.callout` medium (the History window's and the History page's filters) |
| Text button | System sizes: `.controlSize(.small)` in rows, `.regular` in banners and Settings, `.large` for an empty-state action. In a banner at S, `.small`, and the buttons stack when they don't fit side by side |
| Track row | 40 tall (S), 44 (M), 52 (L); artwork 28 / 32 / 40; the whole row is the hit target (the History page and the History window) |
| Seek / volume track | 4 pt at rest, 7 pt when active; 20 pt tall hit strip across the full width |
| Resize zones | 16 × 16 corner, 6 pt along edges |

---

## 4. Interaction model

### 4.1 Pointer
- **Hover** over the player reveals controls (`Motion.reveal`). Moving away conceals them at once: `Motion.conceal` starts the moment the pointer leaves the window, with no grace period, and a pointer coming back reverses it from where it is (§13.28). While the seek or volume knob is being dragged, or a popover from the player is open, the controls stay until that ends, as before.
- Every interactive element has a hover state: icon buttons get a `fillQuaternary` circular backing at `Motion.snappy`; rows get a full-width `fillQuaternary` rounded backing.
- **Press** feedback on mouse-down (`Motion.press`). The action commits on mouse-up inside the element. Dragging out cancels.
- **Drag** anywhere on the artwork that isn't a control to move the window. The window moves 1:1 with the pointer and respects the grab offset.
- **Resize** from the bottom-trailing corner handle, or any edge when the pointer shows a resize cursor. Square styles stay square; the other shapes resize by width and their height follows (§7).

### 4.2 Trackpad gestures (enhancements, never the only path)

| Gesture | Action |
| --- | --- |
| Two-finger horizontal swipe | Move between surfaces: 1:1 tracking, rubber-band at the ends, momentum projection (deceleration 0.998), settle with `pageMomentum` |
| Two-finger horizontal swipe on the Now artwork, with "Swipe to skip" enabled | Next or previous track instead of the surface change (user setting; off by default) |
| Two-finger vertical swipe on the Now artwork | Volume, with a HUD capsule (§5.8) |
| Pinch | Resize the player between size classes |

Gesture rules:
- Lock the axis after 12 pt of travel.
- Commit by projected endpoint and velocity sign, not by raw distance.
- Haptic feedback (`NSHapticFeedbackManager`, `.alignment`) fires exactly when a page settles, never during the drag. The window snap has its own (§4.5).

### 4.3 Keyboard

Every action has a keyboard path. Shortcuts follow Apple Music where one exists. *Amended 2026-11-07 by the redesign (§13.9–§13.18).*

| Keys | Action |
| --- | --- |
| Space | Play / Pause |
| ⌘→ / ⌘← | Next / Previous track |
| ⌘↑ / ⌘↓ | Volume up / down |
| ⌥⇧B | Favorite the current track (Music and the demo, §1.3) |
| ⌘1 – ⌘3 | Now, History, Status |
| ← / → | Previous / next surface, when the player has focus and no text field is active |
| ⌘, | Settings |
| Esc | Back out one level (§4.6): close the topmost transient (a popover, a menu, the Menu Bar popover); on History or Status in a short style (§7.2), go back to Now |
| ⌘W | Hide Player; in Settings or the Listening History window, close that window |
| Toggle Player (global, configurable, no default) | Show or hide the player from anywhere; in Menu Bar, open or close its popover (§7.1) |
| ↑ ↓ ↩ | Navigate and choose in lists (History, the History window) |

Hum's old search shortcuts (⌘K, ⌘F, ⌘L, ⌘↩, ⌥↩, and the global ⌥⌘K) went with Find (§13.3). A saved global Find shortcut is ignored, never reassigned.

Focus uses the system focus ring (`.focusable()`), with the ring following the shape's corner radius.

### 4.4 Right-click menus

Every song representation has a native context menu. The same menu is available from its `ellipsis` button. *Amended 2026-11-07 by the redesign (§13.9–§13.18).* For a song, in this order:

1. Play Now: on the History page's and the History window's songs; left out for the song that's already playing
2. *(separator)* Favorite (Music and the demo, §1.3)
3. *(separator)* Copy Link · Show in App ("Show in App" brings the music app forward with the song shown; it never names the app, §10)

Right-clicking the player anywhere that isn't a song row adds the **player section** after the song's items:

4. *(separator)* Style ▸: the five window styles in §7 order, the current one checked (*amended 2026-11-08, §13.19*)
5. Pin to ▸: Top Left · Top · Top Right, *(separator)* Left · Center · Right, *(separator)* Bottom Left · Bottom · Bottom Right, the current pin checked (§4.5). Symbol images on macOS 26 only
6. Show ▸: Now (⌘1) · History (⌘2) · Status (⌘3), the current one checked
7. Move to Menu Bar (§7.1)
8. *(separator)* Hide Player

Unsupported actions for the current source are **hidden, not disabled**. Play Next, Add to Queue, Add to Playlist, Go to Artist, Go to Album and Start Station went with Play and Find (§13.9).

### 4.5 Window behavior

*Amended 2026-11-07 by the redesign (§13.9–§13.18).*

- **Pin positions.** The player has nine places on a screen, as macOS's own Move & Resize commands name them: Top Left, Top, Top Right, Left, Center, Right, Bottom Left, Bottom, Bottom Right (`PinPosition`).
  - Corners and edge midpoints sit inset `Spacing.l` from the visible frame (below the menu bar, clear of the Dock); Center is the visible frame's center.
  - The pin is remembered per display, with the size. A player with no pin yet starts at Top Right.
  - When the window changes size or shape (a style switch, a size preset, growing for History or Status, a resize drag), its pinned point stays put: a Top Right player grows down and to the left, a Center player grows from its center, a Bottom player grows upward.
  - Pin to ▸ (§4.4) and Settings › Player › Position (§8) move the player with `Motion.throw` from where it is.
  - A player dragged and dropped with snapping off has no pin: it stays where it was dropped, and keeps its nearest-third anchor for resizing, as before.
- **Drag** moves the window 1:1 and keeps the point you grabbed under the pointer. While dragging, screen edges rubber-band (constant 0.55) rather than stopping hard.
- **Throw to snap.** This is the behavior setting "Snap when thrown" (stored as `snapToCorners`), on by default, and it works like picture-in-picture on Apple platforms.
  - On release, project where the window would come to rest, using its velocity and a deceleration of 0.998.
  - Pick the pin position nearest to that projected point, among all nine, then settle there with `Motion.throw`, carrying the release velocity. The player is now pinned there.
  - A projection that lands on another display moves the window to that display.
  - A trackpad haptic (`.alignment`) fires once, at the moment the window settles.
  - With snapping off, the window stays where it was dropped and carries no momentum.
- **Show and hide** use `Motion.materialize` toward the window's current anchor:
  - Tucked mode ("Under Menu Bar") slides down from the menu bar and back up into it, along the same path. It uses the top position in the pin's column (a Center or Bottom pin tucks at Top).
  - Show-on-track-change appears with materialize and hides after 4 s unless the pointer is over the window.
  - Going into Menu Bar materializes toward the status item, and Pop Out Player materializes from it (§7.1).
- **Resize** keeps each style's shape (§7). Crossing a size-class boundary crossfades the content (`Motion.smooth`) instead of jumping.
- **Focus:** the panel is non-activating. Apart from VoiceOver (below), it never activates Hum, and it doesn't take key focus when it appears, on hover, or on a track change. It becomes key, still without activating Hum, only when the user clicks it or summons it: a surface or Show Player from a menu or a shortcut. Then its shortcuts (§4.3) work, as the Music MiniPlayer's do once clicked. Under VoiceOver, Hum activates when the player takes focus, so VoiceOver can reach it.

### 4.6 Feedback

Hum uses Apple's four kinds of feedback, each with exactly one form:

| Kind | When | Form |
| --- | --- | --- |
| **Status** | Something is ongoing | Inline: the progress line, the waveform marker, or "Connecting to Kitchen…" in `DeviceRow`. A small spinner appears only after 400 ms. |
| **Completion** | An action finished and its result isn't visible | The HUD (§5.8), e.g. "Added to Favorites" |
| **Warning** | Degraded, but still working | An inline banner with an orange glyph that can be dismissed |
| **Error** | Hum can't do what was asked | An inline banner with a red glyph and one recovery action. It stays until resolved or dismissed. Never a modal alert, never a toast that vanishes before it can be read. |

- **Optimistic, then honest:**
  - Transport state flips the moment the action commits.
  - A shuffle, repeat, volume or position Hum sets stands for 1.5 s against the app's replies, until one agrees, since Spotify answers before it takes the value; then the app's word is final (§13.34).
  - If the source doesn't confirm within 1.5 s, the state reverts with `Motion.smooth` and nothing else is shown.
  - If the same failure happens twice in a row, a warning banner explains it.
- **Loading** placeholders are static `fillQuaternary` shapes. No shimmer, no pulsing skeletons.
- **Sound:** Hum makes no UI sounds.
- **Haptics** fire only when a page settles and when the window snaps. Buttons never trigger haptics.
- **Wayfinding:** the page indicator appears whenever the page changes and shows where you are (§6, §13.21), Esc always backs out one level, and every surface has a name for VoiceOver and the menus.

---

## 5. Building blocks

Hum is assembled in five layers. Each layer may only depend on the layers below it.

```
Tokens ─▶ Primitives ─▶ Components ─▶ Patterns ─▶ Surfaces ─▶ Styles
(values)  (views with   (single-       (reusable    (Now, History,  (presets that
           no product    purpose UI     arrangements  Status)     re-skin surfaces
           meaning)      with meaning)  of components)             via tokens)
```

### Building-block principles
1. **One responsibility per component.** A component renders one concept: a seek bar, a save button, a track row. Layout belongs to the parent.
2. **State in, intents out.** Components receive plain values (or a small observable model) and emit intents (`PlayerActions`). They never call a playback source directly.
3. **Capability-gated, not if-gated.** A component asks the source's capability flags whether it may appear. If a capability is missing, the component isn't rendered, so there is no dead UI.
4. **Size-class aware, not pixel aware.** Components read the player size class (§6.1) from the environment and pick token values. They never measure the window themselves.
5. **Every component ships its states:** default, hover, pressed, focused, disabled-or-hidden, loading, empty, error. It also ships the four accessibility variants: VoiceOver label and value, Reduce Motion, Reduce Transparency, and Increase Contrast.
6. **Previewable.** Every component has a SwiftUI preview driven by the demo source, covering light and dark at S and L.
7. **No magic numbers.** Every value comes from a token. A new value means a new token, added to this spec.
8. **Native control first.** Wrap `Slider`, `Menu`, `TextField`, and `Toggle` and restyle within HIG limits before building a custom control. Custom controls (seek bar, pager) must replicate native accessibility behavior.

### 5.1 Primitives
| Primitive | Responsibility |
| --- | --- |
| `HumText` | Applies a `HumType` role (font, weight, color, monospaced digits) |
| `HumIcon` | SF Symbol at the size class's glyph size, rendering mode, and weight |
| `ArtworkView` | Async artwork with the one missing-artwork placeholder (§3.4) at every size, radius token, shadow token, and crossfade on change |
| `MaterialBackground` | Renders a `HumMaterial`, including Reduce Transparency fallbacks |
| `Scrim` | The `controlsScrim` gradient |
| `CapsuleTrack` | Track plus fill for sliders: 4 pt at rest, 7 pt when hovered or dragged |
| `Badge` | The explicit symbol |

### 5.2 Transport components
- **`PlayPauseButton`**: the primary control.
  - Over artwork (Art Only, Now hover): a bare glyph at primary size with a soft shadow for legibility (Apple MiniPlayer).
  - On material (Title, Text, Strip, Big Art, the Menu Bar popover): the same bare glyph in `label`, with no shadow, as in Apple Music's player panels (§13.2).
  - The glyph morphs with `.symbolEffect(.replace)` when the action commits. Sizes follow §3.8, and states follow button family 1 in §5.9.
- **`SkipButton`** (next/previous): transport glyph family (§5.9) at secondary size, with a `.bounce` symbol effect when the action commits. Holding it for 0.5 s scans backward or forward for as long as it is held, when the source supports it (capability-gated). Releasing resumes normal playback.
- **`ShuffleButton` / `RepeatButton`**: tertiary glyphs, three-state. Every style's transport has them, on by default, wherever the source supports them (§1.3, §13.11).
  - **Active state:** the glyph takes `accent`, with a 4-pt `accent` dot centered under it and no backing, as in Apple Music.
  - Repeat cycles off → all → one with `repeat` → `repeat` (active) → `repeat.1` (active), with every source (§13.24). Between `repeat` and `repeat.1` the glyph cross-fades with the toggle's own animation (`Motion.snappy` from the button, `Motion.smooth` from elsewhere), in step with the color and the dot; it doesn't use the symbol's replace effect, which runs about twice as long (§13.34).
  - **Repeat one with Spotify.** Spotify's app has only repeat on and off, so Hum provides one: choosing One keeps Spotify's repeat on (Hum shows `repeat.1`), and about 2 s before the song ends Hum re-reads the position and sets it back to 0, so the song starts over without a gap. Spotify takes a new position a moment after it answers, so the restart leaves it that long to land (§13.34). Hum reschedules this on every state update and cancels it on pause, a track change, or a mode change. If the song still ends (a missed timing, a restart Spotify took too late, the Mac asleep), Hum goes back to it with Previous Track once: a change to another song in the last 3 s, or until 1.5 s past the song's old end after a restart, counts as the song ending. Next or Previous while One is on moves to that song and keeps One, as Apple Music does. If the user turns Spotify's repeat off in Spotify, One ends. One isn't saved: after Hum relaunches, a Spotify with repeat on shows All. Each restart counts as a new play in History (§6.5).
  - **Repeat one's note.** Spotify's own repeat button can't show One, since Hum can only turn its repeat on or off, so picking One there changes nothing in Spotify's window. The first time the user picks One on the repeat button for an app like this, a system popover from the button (§5.11) says so once: `repeat.1` in `accent`, "Hum Repeats This Song", and "Your music app can’t show repeat one, so its own repeat button stays on. Hum starts the song over just before it ends." It doesn't name the app (§10). Like the volume popover, it holds the controls up and closes on an outside click, on Esc, and when the player hides. Hum remembers that it was shown, and never shows it for Music, whose own button shows One (§13.35).
  - The VoiceOver value states the mode ("Repeat, one song").
  - **`SaveButton`**: the Favorite star (§3.4). It's hidden while Spotify plays, because Spotify's app doesn't let other apps save songs (§1.3).
  - Toggling on plays `.symbolEffect(.bounce)` and fills with accent; toggling off just reverts the glyph.
  - Shows a brief "Added to Favorites" HUD (§5.8) only when invoked by keyboard or the menu, where the button may be off-screen.
- **`SeekBar`**: a `CapsuleTrack` spanning the controls width. Its full behavior is in §5.10.
  - **Apple's white scrubber**, as in Music's MiniPlayer and Now Playing. *Amended 2026-11-07 by the redesign (§13.9–§13.18).* Over artwork, a scrim or platter, `artBackdrop`, or any material in dark appearance: the elapsed fill is white, the rest of the track white at 30%, and the time labels white at 60%. On a light material in light appearance (Title, Text, Strip; the Menu Bar popover) it is the same design in `label` and `label` at 20%, as Apple's controls are on light materials. The fill never uses the accent.
  - 4 pt at rest, 7 pt while hovered or dragged (`Motion.snappy`). There is no knob: the end of the fill is the playhead, as in Apple's scrubber. Dragging scrubs 1:1, shows the target time in the elapsed label, and commits on release.
  - At S, and as Strip's seek notch (§7), it is the bar alone, without labels; the hover preview tag (§5.10) shows the time.
  - Labels show elapsed at the leading edge and remaining ("−1:23") at the trailing edge. Clicking the trailing label switches it between remaining and total, and the choice is kept as a behavior setting. A time that isn't known yet (loading, a stream) reads "--:--".
  - Accessibility: an adjustable element whose increment and decrement steps are 5 s, and whose value reads "1 minute 2 seconds of 3 minutes 40 seconds".
- **`RestingIndicator`**: Art Only's progress while the controls are hidden. Settings offers None (the default: the cover alone), Line (a 2-pt hairline along the bottom edge of the artwork), or Ring (2 pt, drawn inside the panel edge).
- **`VolumeControl`**: `speaker.fill` · `CapsuleTrack` · `speaker.wave.3.fill`, behaving like the seek bar. At S size it collapses to a single speaker glyph whose waves fill with the level (`variableValue`); it opens a vertical capsule slider in a popover. Scroll wheel over it adjusts volume.

### 5.3 Track identity components
- **`TrackHeader`**: title (`trackTitle`) with the explicit badge inline after it, then one secondary line, "Artist — Album" (artist in `trackArtist`, album in `trackAlbum`), where §7 shows the album (L in the square styles, M and L in Big Art). Otherwise, or when the album is off or empty, the line is the artist alone. There is never a separate album line.
  - On a track change, it animates per `Motion.trackChange`.
- **`SourceBadge`**: *retired 2026-11-07 (§13.15).* The player, its menus and widgets don't name the music app; the Status page does (§6.3).
- **`DeviceRow`**: "Playing on Kitchen" with `hifispeaker.2` in `accent` and the name in `caption`, secondary. When playback is on another device (AirPlay in Music), it is the last line of `TrackHeader` at M and L, never a separate row under the transport. Clicking it opens the device picker.

### 5.4 Marquee rule
A title that doesn't fit scrolls once, only while the pointer hovers over it: a 1.0-s delay, then 30 pt/s, then a 1.5-s pause at the end, then it snaps back with a fade. It never scrolls without hover, and never under Reduce Motion.

### 5.5 List components

These serve the History page and the History window. Components only Play and Find used (`QueueSectionHeader`, the queue's rows) were deleted with them (§13.9).

- **`TrackRow`** (height 40 at S, 44 at M, 52 at L):
  - Layout: leading artwork at 32/40 pt with `artSmall` radius; title and artist stacked; duration trailing (tertiary, monospaced digits).
  - The playing row shows `waveform` in `accent` in place of the artwork's play overlay. Its title stays `label`, as in Music's lists.
  - Hover replaces the artwork with a 12-pt play glyph overlay (`ArtworkDim.row`) and reveals the `ellipsis` button at the trailing edge.
  - The glyph over the artwork is part of the row, not a separate button: a click on it plays. Keyboard and VoiceOver reach it through the row (↩, the row's Play action).
  - Double-click or ↩ plays.
- **`MediaCard`**, where History or the History window shows a grid of albums or artists: artwork (`artMedium`, square) with `cardTitle` and a one-line subtitle. On hover a circular play button in `accent` rises 4 pt into the artwork's bottom-trailing corner and the art dims by black 12%. Artists use circular artwork and no play button. If no surface uses it any more, it is deleted.
- **`EmptyState`**: at M and L, the system `ContentUnavailableView` (symbol, title, description, at most one action). At S, where it doesn't fit, Hum's compact version: a centered symbol (28 pt, tertiary), a short title, a short explanation, and at most one button. Both wrap rather than truncate; the title may take two lines. The copy is factual: the title "No Listening Yet", the description "Songs you play will appear here."

### 5.6 Search components

*Retired 2026-11-07 with Find (§13.9).* The History window keeps the system search field (`.searchable`) it already had.

### 5.7 Insight components (History)
- **`InsightCard`**: a `fillQuaternary` fill with `Radius.card` and `Spacing.l` padding, with a 1-pt `separator` edge under Increase Contrast. It is content, so it never takes glass (§3.6).
  - Content: one `statValue` (rounded numerals), one `statLabel`, and an optional one-line plain-language explanation that includes the time range ("since you installed Hum on Nov 4").
  - At most two cards visible in the mini player. Clicking a card expands it in place (`Motion.smooth`).
- **`SessionRibbon`**: duration · songs · artists, plus a horizontal trail of 20-pt artwork thumbnails (`artSmall`), oldest at the leading edge, ending at the current track. The trail's end marks the current track; no ring or other marker is drawn.
- **`MiniTimeline`**: dots on a hairline showing first heard → recent returns. No axes, no gridlines.
- **`HeatCalendar`** (expanded view only): a month grid of 10-pt rounded squares, accent at 5 opacity steps, plus the weekday initial row. No legend beyond "Less ··· More". Clicking it never rings the whole calendar: it takes keyboard focus without the system focus effect (`.focusEffectDisabled()`), and the arrow keys move the day selection, whose own ring shows where you are (*amended 2026-11-09, §13.31*).
- Swift Charts may be used in the expanded history view only. Never use 3D, gradients, or more than one accent hue per chart.

### 5.8 System and feedback components
- **`PermissionBanner`**: when Automation access to the music app is missing, shows an inline banner on Now: "Hum needs your permission to control your music app.", an "Open System Settings" button deep-linking to Privacy & Security › Automation, and "Not Now". It doesn't name the app (§10); the Status page does, with the same button (§6.3). It never shows as a modal alert. In Title, Text and Strip, which are too short for it, it shows only on Status.
- **`HUD`**: a centered capsule on `glassCard` material showing a glyph plus a short label (volume level, "Added to Favorites"). It fades in at `Motion.reveal` and out after 1.2 s; on macOS 26 it materializes with the system glass transition instead, and under Reduce Motion it only fades. In Title, Text and Strip, which are too short for it, its glyph and label take the place of the window's content for those 1.2 s, then the content returns. It never covers the title or Save it is confirming. It is used only for actions whose result isn't otherwise visible.
- **`DevicePicker`**: a popover from `DeviceRow` or the devices button listing devices (`laptopcomputer`, `hifispeaker.fill`, `tv.fill`, `iphone`, `headphones` glyphs: the filled form wherever one exists). The current device has `accent` and a checkmark. It mirrors the AirPlay picker's layout. Spotify has no picker (§1.3).
- **`StatusMenu`**: the menu-bar item. *Amended 2026-11-07 by the redesign (§13.9–§13.18).*
  - **The item shows Hum's mark**: the Vibrato logo as a template image (drawn from `design/logo/hum-symbol-small.svg`, 18 pt tall in the standard square item), not an SF Symbol. When no music app is available it is dimmed (`appearsDisabled`), and VoiceOver hears "Hum, no music app available". Its tooltip is "Title — Artist".
  - **The menu is lean**, only what people use from the menu bar:
    1. The song as two disabled lines: the title, then the artist; or "Nothing Playing". They are plain disabled items, so both draw in the system's disabled color, as Apple's own information lines in a menu do (AppKit ignores a color set on a disabled item's title). Each line is tail-truncated to 145 pt in the menu font (13 pt), so the menu is at most about 220 pt wide whatever the song (the menu adds its insets and the key-equivalent column) (*amended 2026-11-09, §13.25*). Its tooltip is the full "Title — Artist". No source subtitle.
    2. Play or Pause, Next Track, Previous Track, each hidden when the source can't do it.
    3. *(separator)* Show Player, titled Hide Player while the player is showing (with the global shortcut when the user has set one; there's no default). In Menu Bar (§7.1) it is Pop Out Player. Then Listening History…, which opens the Listening History window (§6.5, §13.25).
    4. *(separator)* Settings… (⌘,) and Quit Hum (⌘Q).
  - Shuffle, Repeat ▸, the surfaces, and About Hum left the menu: they live on the player and in Settings › Hum.
- **`MenuBarPlayer`**: the status item and popover of the Menu Bar style (§7.1).

### 5.9 Button system

Every button in Hum belongs to one of ten families (family 2 is retired). There are no one-off button styles.

| # | Family | Looks like | Used for | Implementation |
| --- | --- | --- | --- | --- |
| 1 | **Transport glyph** | Bare SF Symbol, no backing at rest | Previous, next, and play/pause over artwork | `PlayerButtonStyle(.transport)` |
| 2 | **Primary filled** | *Retired in v1 (§13.2).* Play/pause uses the transport glyph on every style, as in Apple's players | — | — |
| 3 | **Toggle glyph** | Bare glyph; when on, an accent glyph with a 4-pt accent dot under it | Shuffle, repeat, save | `PlayerButtonStyle(.toggle)` |
| 4 | **Icon** | Bare glyph with a circular backing on hover | More, devices, clear, remove, Pop Out Player | `PlayerButtonStyle(.icon)` |
| 5 | **Text** | System push button | Banners and empty states on the player | `.borderedProminent` (one per view, accent), `.bordered`, `.borderless` |
| 9 | **Action** | A soft rounded tile with a hairline edge: an optional accent symbol, then the title (*added 2026-11-09, §13.27*) | Every button in Settings, the buttons in the Listening History window's content (its toolbar keeps system toolbar items), and the Status page's buttons (§6.3) | `ActionButtonStyle`, `ActionLabel` |
| 10 | **Pill menu** | Family 9 as a capsule, with the current choice and a chevron (*added 2026-11-09, §13.31*) | The Listening History window's filter and period menus | `PillMenu`: a `Menu` drawn with family 9's tokens as a capsule |
| 6 | **Floating play** | Accent circle that rises into the artwork on hover | Media cards (History, the History window) | `PlayerButtonStyle(.cardPlay)` |
| 7 | **Chip** | Capsule with a text label | The History page's and the History window's filters | `PlayerButtonStyle(.chip)` |
| 8 | **Card** | The whole card is the button; no backing | Media cards, insight cards | `PlayerButtonStyle(.card)` |

**States** (an empty cell means the state doesn't apply):

| Family | Rest | Hover | Pressed | Focused | On | Unavailable |
| --- | --- | --- | --- | --- | --- | --- |
| Transport | `label` glyph | `fillQuaternary` backing fades in (`snappy`) | `fillTertiary` backing, glyph scales to 0.88 | System focus ring on the backing shape | — | Hidden. While a source is loading: `quaternaryLabel` |
| Toggle | `secondaryLabel` glyph | `fillQuaternary` backing; the glyph stays `secondaryLabel` | `fillTertiary`, scale 0.88 | Focus ring | Shuffle and repeat: accent glyph with a 4-pt accent dot under it, always (so it never depends on color alone). Save: the filled glyph (`star.fill`, `checkmark.circle.fill`) in accent and no dot, because its shape already shows the state | Hidden |
| Icon | `secondaryLabel` glyph | Backing appears, glyph becomes `label` | `fillTertiary`, scale 0.88 | Focus ring | — | Hidden |
| Text | System | System | System | System | — | System disabled look. This is the only family allowed a disabled state, e.g. while a form is incomplete. |
| Floating play | Hidden | Rises 4 pt and fades in when its card is hovered (`snappy`) | Scale 0.92 | Focus ring; also shown when its card has focus | — | — |
| Chip | `fillQuaternary` capsule, `label` text | `fillTertiary` | `fillTertiary`, no scale | Focus ring on the capsule | Selected: `label` fill with inverted text | Hidden |
| Card | Artwork and title, no backing | The floating play rises; standard art dims by black 12% (§5.5) | Scale 0.98 | Focus ring on the artwork's shape | — | — |
| Action | `primary` at 5% fill, 1-pt `primary` 10% edge, corners 9 (7 compact); title 12 pt medium (11 compact) in `label`, symbol 11 pt semibold in `accent` | Fill 10%, edge `accent` at 45% (`Motion.easeOut(0.12)`) | `accent` 20% fill, 1.5-pt `accent` edge, a soft `accent` glow (45%, radius 5), scale 0.97 | Focus ring on the tile's shape | Selected (a two-way switch such as the preview's Light and Dark): 10% fill, 1.5-pt `accent` edge, semibold title, `.isSelected` | `tertiaryLabel` title, opacity 0.6; the only other family allowed a disabled state |
| Pill menu | Family 9's rest, as a capsule; the current choice in `label` 12 pt medium, then a `chevron.down` 9 pt semibold in `secondaryLabel` | As family 9 | As family 9, scale 0.97; the system menu opens on mouse-down | Focus ring on the capsule | A filter that isn't "Any": the choice in `accent` and the edge `accent` at 45% | Hidden |

**Press behavior (all families):**
- Pressed visuals start on mouse-down with `Motion.press`. The action commits on mouse-up inside the target, with the hysteresis from §3.8. Releasing springs back with `Motion.snappy`.
- Scale amounts: small glyph buttons 0.88; the floating play circle 0.92; cards 0.98; action buttons and pill menus 0.97; chips don't scale; rows don't scale (they highlight instead); text buttons use the system's own press.
- Symbol effects (`replace`, `bounce`) play when the action commits, never on press.
- Keyboard activation (Space or Return while the focus ring is visible) plays the same press-and-release sequence.
- Holding previous or next for `holdDelay` (0.5 s) scans, where the source supports it (§13.7).

**Placement (shared by Apple's player and Spotify):**
- The transport order is always **shuffle · previous · play/pause · next · repeat**, centered on play/pause, on every style (§7). The menu-bar item itself shows only play/pause and next (§7.1).
- **Save and More sit at the trailing end of the title row**, where both Apple Music and Spotify put them, never in a corner.
- At most one prominent Text button is visible at a time.
- Destructive buttons appear only in Settings, as action buttons whose symbol and title are `systemRed`. Only irreversible actions (Erase All History, Remove Imported History) ask for confirmation.

**Every icon-only button has a tooltip** (`.help`) with its name and shortcut, such as "Next Track (⌘→)". The cursor stays the arrow, as with native macOS buttons.

### 5.10 Sliders (seek and volume)

- **Track:** a `CapsuleTrack`, 4 pt at rest and 7 pt on hover or drag (`Motion.snappy`), with a 20 pt hit strip. The seek bar's colors are Apple's white scrubber (§5.2); the volume slider's are the same.
- **Click** anywhere on the track to jump there. The fill moves with `Motion.smooth`.
- **Drag** tracks 1:1 and keeps the grab offset, so grabbing the end of the fill doesn't make it jump. The pointer is captured, so dragging outside the window keeps scrubbing. During a drag the fill follows the pointer exactly, with no animation.
- **Fine scrubbing:** hold ⌥ while dragging to scrub at quarter speed. This is the Mac equivalent of iOS's slide-down-to-scrub-slowly.
- **Hover preview** (the seek bar at M and L, and Strip's seek notch): a small time tag follows the pointer above the track, showing the time under the pointer. It uses the `time` text style with `Radius.control`: on `popover` material over artwork, and on a `fillTertiary` fill (no material) on a glass card or a glass window, so glass never sits on glass.
- **Commit:** a seek is sent once, on release, not continuously. The UI shows the new position immediately, and interpolation resumes from it.
- **Ends clamp** without rubber-banding. At zero volume, the leading glyph becomes `speaker.slash.fill`.
- **Scroll:** two-finger scrolling over the volume slider changes the volume. Scrolling over the seek bar does nothing, so the song never jumps by accident.
- **Keyboard** (when focused): ←/→ seek 5 s, or ⇧ for 15 s; volume steps 5%.
- **Accessibility:** adjustable elements with spoken values (§5.2).

### 5.11 Menus, popovers, tooltips, and cursors

- **Menus** are native (SwiftUI `Menu` and context menus, backed by `NSMenu`). They are never custom-drawn.
- **Popovers** (device picker, volume at S size, the Menu Bar popover) are system popovers (SwiftUI `.popover`), never custom-shaped. They point at their trigger and close on an outside click or Esc. The system draws their material, and Liquid Glass on macOS 26.
- **Tooltips** use system help tags with the shortcut in parentheses.
- **Cursors:**
  - The arrow everywhere by default, including on buttons, rows, and the draggable artwork.
  - Resize cursors in the resize zones, and the I-beam in text fields.
  - Title and artist links underline on hover; the cursor stays the arrow.

---

## 6. Surfaces

**Page indicator.** One mark per surface (Now, History, Status) in a glass capsule, centered along the top of the player; the mark for the page in view is the wide one, and the marks track a swipe continuously. *Decided 2026-11-08 (§13.21): the indicator marks a change rather than staying on screen.*
- **Hidden at rest and on hover**, on every surface. Hovering Now or History or Status doesn't bring it.
- **Appears when the page changes:** from the moment a two-finger swipe starts tracking, and on ⌘1–⌘3, Show ▸ or Esc back to Now. It comes in with `Motion.reveal` (opacity only under Reduce Motion), follows the swipe, stays 1.5 s after the page settles, then fades with `Motion.conceal`. A new change restarts the 1.5 s. A swipe that rubber-bands at the ends and settles back counts too.
- Surfaces keep their top clearance for it, so it never covers content when it appears.
- While hidden it takes no clicks and VoiceOver doesn't see it. VoiceOver moves between surfaces with the player's Next Surface and Previous Surface actions, and each surface has a name (§9).
- The bar styles (Title, Text, Strip) and Menu Bar have none, as before (§7.2).

### 6.1 Player size classes

The size classes apply to Art Only, the one square style, and to History and Status at any size. The other shapes have their own sizes (§7). *Amended 2026-11-07 by the redesign (§13.9–§13.18).*

| Class | Side (pt) | What is visible on hover |
| --- | --- | --- |
| **S** | 168–239 | Play/pause, skip, shuffle and repeat, the seek bar alone, save |
| **M** | 240–379 (the default, 280, for every square style) | + title and artist, the seek bar with times |
| **L** | 380–640 | + the album on the artist line ("Artist — Album"), volume, the device button |

Content inset per class: S `Spacing.s`, M `Spacing.m`, L `Spacing.l`. The window remembers its size per display and per style.

### 6.2 Now

- Now is the current song in the chosen style (§7). Each style says what shows at rest and on hover.
- **Paused:** covers don't scale; the play glyph shows. *(The padded layouts that scaled their art retired with Glass, Data and Session, §13.19.)*
- **No source:** in the square styles and Big Art, `EmptyState`, titled "Nothing Playing", with the description "Start music in your music app." In Title, Text and Strip, the words "Nothing Playing" in the title's place. In Menu Bar, the item shows Hum's mark alone.

### 6.3 Status

*Added 2026-11-07 (§13.9), after History: which app Hum follows, and whether Hum may control each one.* It replaces Play's place in the pager. Status is the one place on the player that names the music apps.

- **Backdrop:** `artBackdrop` under `windowWash`, as History. Content scrolls when it doesn't fit, at every size class.
- **Connected to** (a `fillQuaternary` card, `Radius.card`): the app's own icon at 32 pt, from its bundle through `NSWorkspace` (§3.5.7; Hum's own icon for the demo), its name in `rowTitle` semibold, and one status line in `rowSubtitle`, secondary: "Playing", "Paused", "Open, nothing playing", "Not open", or "Not installed". When Settings › Sources is Automatic, a caption adds "Chosen automatically". With no app available at all: the title "No Music App" and the line "Install Music or Spotify, or open one of them."
- **Apps** (a `sectionHeader`, then one row per supported app, Music then Spotify, in a `fillQuaternary` card): the app's own icon at 20 pt (as in Connected to) and its name, then its state, trailing:
  - **Allowed**: `checkmark.circle.fill` in `secondaryLabel` and the word "Allowed" (no green, §3.5.6).
  - **Not allowed**: `exclamationmark.triangle.fill` in `warning` and "Not allowed", with an "Open System Settings…" button (family 9, compact) to Privacy & Security › Automation.
  - **Not asked yet**: `questionmark.circle` in `tertiaryLabel` and "Not asked yet", with an "Allow…" button (family 9, compact) that asks macOS, which shows its own prompt.
  - **Not open**: "Not open" in `secondaryLabel`, with no glyph and no button. macOS reports an app's permission only while the app runs, and Hum never opens an app on its own to ask. *Added 2026-11-07.*
  - **Not installed**: the row dims (`tertiaryLabel` text, the generic app glyph) with "Not installed".
  - The rows refresh when Status appears and when Hum becomes active again, never on a timer.
- **Footer:** a "Settings…" action button (family 9, with `gearshape`) that opens Settings › Sources. *Amended 2026-11-09: the button matches the other Settings buttons, and the rows' buttons follow, so the page has one button style.*
- Status shows no account, sign-in or connect action: Hum has none (§1.3).
- VoiceOver reads each row as one element: "Spotify, not allowed" or "Music, not open", with the button, if any, as its action.

### 6.4 Find

*Retired 2026-11-07 (§13.9), with Play.*

### 6.5 History

*Renamed 2026-11-09 (§13.23). The page's stored value stays `echo`, so saved placements and `--surface echo` still work.*
- **Default:** at most two `InsightCard`s, one about the song and one about the session, chosen by relevance.
- History sits on the same backdrop as Status: `artBackdrop` under `windowWash` (§3.6), so text on its fills keeps 4.5:1 over any cover.
- "See All" opens the expanded history view in a separate standard window, the **Listening History window**. It has a sidebar (This Week, Calendar, History, Top, Rediscover) and uses `HeatCalendar`, a music receipt, and filters. *Amended 2026-11-09 (§13.31):*
  - **It opens with the sidebar collapsed**, so the content gets the whole window; the standard sidebar button in the toolbar brings it back, and the window remembers the choice while Hum runs. Each open after a relaunch starts collapsed.
  - **Its menus are pill menus** (§5.9, family 10): Any Artist, Any Album, Any Playlist (shown only when some listening has one), Any Time, and Top's period (This Week, This Month, This Year, All Time). They match Settings' action buttons and the Line apps' pill buttons: a capsule with a hairline edge, the choice in 12-pt medium, and a chevron. Buttons in its content (the paused note's Resume, Clear Filters, empty states) are action buttons (family 9); its toolbar keeps system toolbar items.
  - **Top ranks songs, artists and albums.** Playlists left Top: Spotify's app doesn't say which playlist a song plays from, so Top couldn't rank it for most listening. The Any Playlist filter stays, hidden when nothing has a playlist.
  - It is the one Hum window that brings the Dock icon and the main menu (§8, §13.26).
- Every number states its range and source ("tracked since install", "imported"), without naming the music app on the player (§10). A range or source line that is a sentence is set in `secondaryLabel`, not `tertiaryLabel` (§3.5.9).
- Spotify's app doesn't say which album or playlist a song plays from. History never guesses one for Spotify listening; insights that need it appear for Music and the demo only.
- When collection is paused, a quiet inline note appears with a Resume button. There are no warnings or red.

---

## 7. Styles (presets)

A style is a named set of token overrides plus a layout and window shape for Now. Styles never add components the building blocks don't define. *Amended 2026-11-07 by the redesign (§13.9–§13.18).* Six new styles joined Glass, Data and Session, which shrank. *Amended 2026-11-08 (§13.19): Glass, Data and Session are retired, leaving six styles.* Minimal became Text and Compact became Strip; their stored values stay `minimal` and `compact`, so saved settings carry over. *Amended 2026-11-09 (§13.29): Wide joins, and Big Art is rebuilt on an outlined card like Wide's; the old edge-to-edge Big Art is gone.*

Order everywhere: Art Only, Title, Text, Strip, Wide, Big Art, then Menu Bar in the Settings tiles. Style ▸ lists the six window styles in that order, and Menu Bar is its own menu item (§4.4). A saved `glass`, `data` or `session` style opens as Art Only, the default (§13.19).

| Style | Shape (pt) | At rest | On hover | Material |
| --- | --- | --- | --- | --- |
| **Art Only** (default) | Square 168–640, default 280 | The cover, nothing else. Resting progress: None (default), Line or Ring | Everything: title and artist (album at L), Save and More, the seek bar (with times from M), shuffle · previous · play/pause · next · repeat, volume and devices at L | `controlsScrim`, or `controlsPlatter` with Liquid Glass |
| **Title** | 72 tall; 240–420 wide, default 300 | The cover at the leading edge (56 pt, inset 8, `artMedium`), then the title over the artist | The title and artist give way to the controls in the same column: the transport on top, the seek bar below it | `glassCard` at the window level |
| **Text** | A capsule 44 tall; 180–360 wide, default 240 | The title over the artist, nothing else | The words give way to shuffle · previous · play/pause · next · repeat, spread across the capsule | `glassCapsule`; optional album tint |
| **Strip** | 48 tall; 260–440 wide, default 320 | The cover (36 pt, inset 6), a short seek bar (the "seek notch"), then shuffle · previous · play/pause · next · repeat. Everything always shows | The notch grows and shows its time tag | `glassCard` at the window level |
| **Wide** | Landscape: 320–520 wide, default 360; height is half the width | The cover at the leading edge, as tall as the card less its insets; beside it the title row (title, artist, Save and More), the seek bar with times, shuffle · previous · play/pause · next · repeat, and the volume row. Everything always shows | The seek bar grows | `glassCard` at the window level, with its 1-pt edge, as Title |
| **Big Art** | Portrait: 220–420 wide, default 280; height is the width plus the controls (§7, Big Art) | The cover inset on an outlined card; under it the title row (title, artist, Save and More), the seek bar with times, shuffle · previous · play/pause · next · repeat, and the volume row. Everything always shows | The seek bar grows | `glassCard` at the window level, with its 1-pt edge, as Title |
| **Menu Bar** | No window: it lives in the menu bar (§7.1) | The cover, the title, play/pause and next, in the menu bar | Clicking opens the Now Playing popover | `popover` |

**Size presets** (Settings › Player › Size: Small, Medium, Large):

| Style | Small | Medium | Large |
| --- | --- | --- | --- |
| Art Only | 200 | 280 | 400 |
| Title (width) | 260 | 300 | 380 |
| Text (width) | 200 | 240 | 320 |
| Strip (width) | 280 | 320 | 400 |
| Wide (width) | 320 | 360 | 440 |
| Big Art (width) | 240 | 280 | 360 |
| Menu Bar | — (the Size row hides) | | |

Per style:

- **Art Only.** At rest it is just the art (§13.10). On hover everything appears at once with `Motion.reveal`: the track header at the bottom leading edge with Save and More at the end of its title row, the white seek bar below it, and the centered transport below that. The page indicator isn't part of the hover (§6). With Liquid Glass the controls sit in the `controlsPlatter`, in white; otherwise on the `controlsScrim`.
- **Title.** The title (`trackTitle`) and artist (`trackArtist`) are one line each and tail-truncate; the help tag shows "Title — Artist". On hover they fade out and the controls fade in (`Motion.reveal`, and back with `Motion.conceal`): the transport row (secondary glyph sizes) top-aligned in the column, and under it the seek bar between its two times (`time`, caption size), or the bar alone below 300 pt wide. No page indicator (§7.2).
- **Text.** The title (`textTitle`) over the artist (`textArtist`), one line each, leading-aligned with `Spacing.l` side padding and vertically centered. On hover the words fade out and the five transport glyphs fade in (shuffle and repeat at the tertiary size, the others at secondary), spread evenly across the capsule. Album tint (off by default) fills the capsule with the palette `background` and sets the text and glyphs in the palette colors (§3.5.4), as Minimal's did.
- **Strip.** No title on screen; the help tag and VoiceOver label read "Title — Artist". The seek notch is a `SeekBar` without labels, at least 56 pt long, taking the width left between the cover and the transport. Corners `Radius.card`.
- **Wide.** *Added 2026-11-09 (§13.29): a card outlined like Title, a little larger, with the title and every control beside the cover.* A landscape card on `glassCard` with its 1-pt `glassStroke` edge and the window corners Title uses. The cover is a square at the leading edge, inset `Spacing.m` on three sides, as tall as the card less those insets, with `Radius.card` corners; nothing sits on it. The column to its right (`Spacing.m` from the cover and from the trailing edge) stacks, top to bottom, with `Spacing.s` between rows and the stack centered vertically: the title row (`trackTitle` over `trackArtist`, one line each, tail-truncated, with Save and More at its trailing end); the seek bar with its two times under it (`time`); the transport at secondary glyph sizes (shuffle and repeat at tertiary), spread across the column; and the volume row (`VolumeControl`: speaker, slider, speaker). On hover the seek bar grows, as in Strip and Big Art; nothing else changes. Text uses the label colors on the material (§3.5.9). Wide is landscape, so History and Status grow it to the 300-pt square, as the bars do (§7.2).
- **Big Art.** *Rebuilt 2026-11-09 (§13.29): outlined the same way, with the controls under the cover.* A portrait card on `glassCard` with its 1-pt `glassStroke` edge and the window corners Title uses. The cover is a square inset `Spacing.m` from the top and sides, with `Radius.card` corners; nothing sits on it. Under it, inset `Spacing.m`, the same stack as Wide's column: the title row, the seek bar with times, the transport, and the volume row. The controls' height is fixed for the style (`controlsHeight`, set so the stack fits with `Spacing.m` below it) and the window's height is the width plus it. On hover the seek bar grows. The edge-to-edge cover and the `artBackdrop` under the controls are gone.
- Shuffle and repeat are part of every style's transport, on by default, and can be switched off per style in Settings › Player (§13.11).

### 7.1 Menu Bar

The last style puts Hum in the menu bar instead of a window (§13.13).

- **Going in.** Choosing Menu Bar (its Settings tile, or Move to Menu Bar in the player's menu, §4.4) hides the player window toward the status item (`Motion.materialize`), and the status item becomes the mini player. Hum remembers the style it came from.
- **The item:** the cover at 18 × 18 pt (corners 4), the song's title in the menu bar's font (`NSFont.menuBarFont(ofSize: 0)`), tail-truncated at 160 pt, then play/pause and next as bare template glyphs (`play.fill` / `pause.fill`, `forward.fill`), each with a 22-pt-wide hit area; 6 pt between pieces. Nothing playing: Hum's mark alone, as in the normal item. VoiceOver reads "Hum, Title by Artist", then "Play" or "Pause" and "Next Track".
- **The Now Playing popover:** clicking the cover or title opens a system popover (`.transient`), 300 pt wide, like Control Center's Now Playing:
  - the cover at 268 pt with `Radius.card` corners, inset `Spacing.l` from the popover's edges
  - the title (`trackTitle` at M, 15 pt, §13.20) and artist (secondary) under it, leading-aligned, with "Pop Out Player" at the trailing end of that row (family 4, `menubar.arrow.down.rectangle`, help tag "Pop Out Player")
  - the white seek bar with times
  - shuffle · previous · play/pause · next · repeat
  - Esc or a click outside closes it. It doesn't steal focus from the frontmost app beyond what a popover must.
- **Right-click or Control-click the item:** the lean menu (§5.8), with Pop Out Player in place of Show Player.
- **Pop Out Player:** the popover closes; the player comes back in the style it had before Menu Bar (Art Only if none), materializing from the status item to its pin; the status item goes back to Hum's mark.
- The Toggle Player shortcut opens and closes the popover while in Menu Bar. Visibility modes (§8) don't apply.

### 7.2 History and Status in the short styles

Title, Text, Strip and Wide are too short for History and Status. Going to either (⌘2, ⌘3, a two-finger swipe, or Show ▸ in the player's menu) grows the window to a 300-pt square, holding its pin, and going back to Now (⌘1, Esc, or a swipe) returns it to its shape, as Compact did. Big Art shows them in its own frame, scrolling where needed, on the same backdrop as Art Only (`artBackdrop` under `windowWash`, §6.5), inside its card's edge. Menu Bar has Now only; its popover never pages.

### 7.3 Widgets

Art Only, Title and Text have widgets (§13.33), in the macOS widget gallery under Hum, built with WidgetKit in a widget extension inside Hum.app. The other displays have none.

*Reopened 2026-11-09 (§13.32).* The hold of §13.30 is lifted, and Hum retires a widget extension left from an older build (below), which is what had frozen the widgets. *Cut the same day (§13.33).* The Text medium, Strip, Wide, Big Art and Menu Bar widgets are gone.

| Widget | Families | Content |
| --- | --- | --- |
| Art Only | small, large | The cover, full bleed. Large adds a `controlsScrim` band with the title, artist, the progress bar and the transport |
| Title | medium | The cover at the leading edge, the title and artist, the transport, and the progress bar |
| Text | small | The title and artist |

- **Live state.** Hum writes a small snapshot (the song, play state, position and its timestamp, shuffle and repeat, and the cover as a PNG) into its Application Support folder, and asks WidgetKit to reload when the song, play state, shuffle or repeat changes, at most once every 2 s. Progress runs on its own with `ProgressView(timerInterval:)` and `Text(timerInterval:)` while playing, and stands still while paused.
- **Buttons** follow the style's transport (shuffle · previous · play/pause · next · repeat, hidden where the source can't do it, shuffle and repeat with their active state). Without Xcode's App Intents tooling they are links to Hum (`hum://` actions) in Title's medium widget and Art Only's large one, so a click reaches Hum without opening a window. Small widgets have no buttons: a click shows the player (§13.16).
- **States:** Nothing Playing shows Hum's mark and "Nothing Playing". A snapshot older than its song's end shows that song paused. Hum not running shows the last song, paused.
- **Older builds.** When Hum.app is replaced in place, by an update or a new build, the widget extension macOS started from the old copy can keep running, and macOS turns down everything it draws because its bundle version no longer matches, so the widgets freeze and Hum's reloads go nowhere. As Hum starts it looks for that process (this user's, running this copy's extension executable, started before that executable was last written, by the later of its modification and status-change times), reads it again to be sure it's the same process, asks it to quit (`SIGTERM`), waits up to 2 s for it to go, and reloads the widgets, so macOS starts the extension from the new copy. An extension started since, or run from another copy of Hum, is left alone. *Added 2026-11-09 (§13.32).*
- Widgets follow the system's appearance and rendering modes (on macOS 26, including its glass and tinted modes). They never name the music app (§10), and they hold nothing but the current song and its cover. Titles are a step larger than the artist line, as on the player (§13.20): `trackTitle`'s M size in small and medium widgets and its L size in large ones, Text's included (its title stays 15 pt over the 13-pt artist, so it never shrinks to the artist's size). Text's title takes up to three lines and its artist two. *Amended 2026-11-08 (§13.19, §13.20): the Glass, Data and Session widgets retired with their styles.*

## 8. Customization and settings

**Look versus behavior.** Settings split into two kinds:
- **Look**: the style is one choice for both appearances. Per style and per appearance (light or dark): accent mode, corners, opacity at rest, and the progress indicator. Per style, shared by both appearances: which controls appear on hover. "Always show controls" and the material (Liquid Glass or Frosted, macOS 26 only) are global.
- **Behavior**, global: the pin position and snapping, always on top, all Spaces, the visibility mode (Always / On Track Change / Under Menu Bar / On Request; stored as `pinned`, `trackChanges`, `tucked`, `summoned`), the trailing time (remaining or total, switched by clicking it), gestures, shortcuts, sources, and history collection.

Rules:
- **Changes apply live.** There is no Save button, and every look change shows instantly in the player and in the Settings preview.
- **Settings window:** a standard macOS Settings window with a sidebar. *Amended 2026-11-09 (§13.26, §13.27).*
  - **The sidebar is grouped by purpose**, as System Settings is: General alone at the top; **Player**: Appearance, Behavior, Shortcuts; **Music**: Sources, History & Privacy; then Hum alone at the bottom. The group titles are the system's sidebar section headers. Behavior is the pane that was called Player (renamed so "Player" names one thing, the group), and History & Privacy was Echo & Privacy; their stored values (`player`, `echoPrivacy`) stay, so `--settings player` and saved selections still work.
  - **Every pane is sections with short purpose headers** (`Section("…")` in the grouped form), for example General: Startup; Appearance: Preview, Style (with Reset Style at its end), Look (Appearance, Material, Accent, Album tint), Details (Corners, Opacity at rest, Progress); Behavior: Controls, Size, Position, Visibility, Window, Gestures; Sources: Music App; History & Privacy: Listening History, What Hum Keeps, Imported History, Your Data; Hum: none on its identity block, then Quit. A section with one row still gets a header. Headers use the title case the panes already use ("What Hum Keeps").
  - **Settings is a utility window.** Opening it never shows Hum's Dock icon or main menu, whatever is open; only the Listening History window brings them (§13.26). It still comes to the front over the frontmost app, and ⌘W, ⌘, and ⌘Q work in it. If the Listening History window closes while Hum is in front and Settings is open, Settings stays in front and key, so closing History never leaves it behind another app.
  - **Hum** (the pane that was About) is like the other Line apps' about panes: Hum's icon at 64 pt, "Hum" in `title` semibold, "Version 1.0.0 (1)" in `secondaryLabel` (selectable; "Development build" without an Info.plist), then centered, at most 380 pt wide, a tagline in `callout` ("The song you're playing, always at hand.") and a `callout` `secondaryLabel` description ("Hum shows what Music or Spotify is playing as a floating window of album art, with the controls there when you reach for them. Your listening history stays on this Mac."), then "Requires macOS 15 or later" and the notice "Covers, titles and playback come from the music apps you use, and belong to their owners. Spotify is a trademark of Spotify AB. Apple Music is a trademark of Apple Inc. Hum is not affiliated with or endorsed by either." in `caption` `secondaryLabel`. A last section: "Quit Hum" (an action button with `power`), labelled "Leave the menu bar" with the detail "Music and Spotify keep playing." "About Hum" in the app menu opens this pane; the standard About panel is gone.
  - Sources holds which app Hum controls. Each app's Automation access lives on the player's Status page (§6.3); a footnote says so: "See whether Hum can control each app on the player’s Status page." There's no account to connect and no playback of Hum's own (§1.3).
  - The pane's name is the window's title, in a unified toolbar; no header is drawn in the pane. The sidebar uses the system sidebar font, with no fixed size and no scale-to-fit.
  - **Buttons are Hum's action buttons** (§5.9, family 9), as in the other Line apps' Settings: Open Login Items…, Reset Style, Open Listening History…, Import Spotify History…, Remove Imported History…, Export as JSON…, Export as CSV…, Erase All History… (destructive, in `systemRed`), Quit Hum. Each sits in a `LabeledContent` row whose label says why you'd press it, and carries a symbol where one says what it does (`arrow.counterclockwise` Reset Style, `square.and.arrow.down` Import, `square.and.arrow.up` Export, `trash` Erase and Remove, `clock` Open Listening History, `power` Quit). *Amended 2026-11-09 (§13.27): the same button style as Glow's, Tuck's and Pulse's Settings.* Buttons inside list rows use the compact variant.
  - Shortcuts are written as plain glyph text ("⌥⌘K") in secondary color, not as drawn key caps.
  - Appearance has a live preview of the player at the top with a Light/Dark switch (two action buttons, Light and Dark, the shown one selected; §5.9 family 9) and a "Show controls" toggle that simulates hover. For Menu Bar it previews the item and its popover.
  - **Choices are visual** (§13.14). Every choice of two to five options, and every bounded slider, is a row of **choice tiles** instead of a pop-up menu, a segmented control or a slider: a small drawing of what the option does, drawn with Hum's tokens and color roles, with its title under it. They use System Settings' own Appearance-tile metrics, the named exception to the 4-pt grid (§3.1): 14 pt between tiles, 10-pt tile corners, and a 3-pt accent ring drawn just outside the chosen tile, with no glow. The title is `.subheadline`, semibold in `label` when chosen and regular in `secondaryLabel` otherwise. Picking a tile applies it live and shows it: the player springs to the size, moves to the position, reveals its controls, and so on. Tiles carry the `.isSelected` trait, are labelled with their titles (drawings hidden from VoiceOver), and take ←/→ and Space when focused.
  - The tiles:
    - Appearance › **Style**: seven tiles, four in the first row and three in the second (*amended 2026-11-09, §13.29*), each drawing the style's shape and layout over the current cover, in §7's order. The Menu Bar tile draws a strip of menu bar with the mini player in it.
    - Appearance › **Appearance**: System · Light · Dark, drawn as small windows, as System Settings' are.
    - Appearance › **Material** (macOS 26 only; not shown on macOS 15): Liquid Glass · Frosted.
    - Appearance › **Accent**: Album · System · Custom, drawn as swatches; Custom reveals the color well.
    - Appearance › **Corners**: Square · Standard · Round, setting the corner radius scale to 0.5, 1.0 and 1.5. A saved value in between marks the nearest tile.
    - Appearance › **Opacity at rest**: 100% · 85% · 70%, each drawing the player over a pattern at that opacity.
    - Appearance › **Progress** (Art Only): None · Line · Ring.
    - Appearance › **Album tint** (Text): Neutral · Album.
    - Behavior › **Size**: Small · Medium · Large, drawn to scale for the current style. Not shown for Menu Bar.
    - Behavior › **Position**: one wide tile drawing a screen with its menu bar and nine targets; the current pin holds a small player shape. Clicking a target pins the player there (§4.5). Under it, the "Snap when thrown" switch.
    - Behavior › **Show the player**: Always · On Track Change · Under Menu Bar · On Request, each drawn (the player present; the player with a note appearing; the player hanging from the menu bar; a key cap).
    - Sources › **Control**: Automatic · Music · Spotify. Music's and Spotify's tiles show each app's own icon from its bundle (§3.5.7), titled with the app's name; Automatic shows both. A tile dims with "Not installed" when its app isn't.
  - Switches stay switches: Open at login, Keep above other windows, Show on every Space, the gestures, and the pieces of the hover controls (each with its glyph as the label's icon).
  - Sidebar pane icons are white glyphs on rounded squares in system colors, as in System Settings.
- **Curated, not exhaustive.** Typography, spacing, and shadow values aren't user-editable in v1, and every slider has a sensible range that can't produce an ugly result.
- **Persistence:** a versioned, typed settings model saved as JSON in Application Support. Built-in styles are immutable; user edits are stored as overrides, so "Reset Style" always works.

---

## 9. Accessibility checklist (per component, per release)

- [ ] VoiceOver label, value, and traits on every control. Custom controls expose adjustable actions (seek, volume, pager).
- [ ] Every action is reachable by keyboard. Focus order follows visual order, and the focus ring is visible. As with native controls, Tab reaches buttons and sliders when the system's Keyboard Navigation setting is on. With it off, playback, volume, Save, the surfaces, and Settings stay reachable through shortcuts (§4.3) and the menu-bar menu (§5.8); shuffle, repeat, pinning and the style are reached through the player's menu (§4.4), with the setting on, and through VoiceOver actions.
- [ ] Reduce Motion: crossfades only, no scale, no marquee, static waveform.
- [ ] Reduce Transparency: opaque materials and a solid scrim.
- [ ] Increase Contrast: full-strength separators and primary-color secondary text.
- [ ] Text contrast is at least 4.5:1 (body) and 3:1 (large text, glyphs), including Album accent mode.
- [ ] Larger text: layouts reflow without clipping, and S size class hides tertiary text before clipping primary text.
- [ ] Light and dark both verified at S and L.

---

## 10. Voice and copy

- Plain, short, and factual. No exclamation marks, no jokes in errors, no "Oops".
- Title Case for buttons, menu items, section headers, empty-state titles, and window and pane titles. Sentence case for Settings control labels, descriptions, captions, banners, and insight sentences (§3.3).
- Typographic punctuation: curly apostrophes and quotes (’ “ ”), the ellipsis character (…), the true minus in times (−1:23), and › between the steps of a System Settings path ("Privacy & Security › Automation").
- One phrase per action across surfaces: "See All" (never "Show All" in one place and "See All" in another).
- Use the source's own vocabulary: "Favorite" and "Station" for Music.
- Never ask the listener to sign in to Spotify or connect an account. Hum has none to connect (§1.3).
- **The player, its menus and its widgets never name the music app**: no "Spotify" (and no "Music" as the app's name) in their text, help tags, or empty states. The Status page (§6.3), Settings › Sources, the History window, and macOS's own permission prompt do name it. *Decided 2026-11-07 (§13.15).*
- Insights read like a friend's observation, not a report: "Usually played late at night", "Your 7th-most-played song this month".

---

## 11. Do and don't

| Do | Don't |
| --- | --- |
| Use SF Pro, SF Symbols, system materials, and system colors | Use custom fonts, Spotify green, or brand-styled chrome |
| Let the artwork fill the window at rest | Show controls, labels, or badges at rest |
| Use springs that start from the current position | Run fixed-duration animations on interactive elements |
| Hide unsupported actions | Show disabled buttons for things a source can't do |
| Use one or two insights with a plain sentence | Build dashboards, charts in the mini player, or streak counters |
| Put context menus on everything | Put actions only behind gestures |
| Give each feature one home | Duplicate features across surfaces |
| Keep idle CPU near zero | Run timers while paused, hidden, or occluded |
| Use the accent only to mark state | Color seek bars, titles, or backgrounds with the accent |
| Use one of the eight button families | Invent a one-off button style |
| Keep the arrow cursor on buttons | Use the pointing hand on buttons |
| Let a thrown window project and settle | Stop the window dead where the pointer let go |

---

## 12. Definition of design done

A component or surface is done when:
1. It uses only tokens from §3. Any new token has been added here first.
2. It implements every state in building-block principle 5.
3. It passes the §9 checklist.
4. It has light and dark previews at S and L, driven by the demo source (`PreviewProvider`s under `#if DEBUG`, which build without Xcode).
5. Screenshots at S and L, in light and dark, at rest and hovered, have been reviewed against this spec.
6. It adds no measurable idle CPU.

---

## 13. Decisions

1. **Save is the Favorite star.** *Decided 2026-11-06 with §1.3: Spotify's app doesn't let other apps save songs, so Save is hidden while Spotify plays and the plus/check glyph is gone.*
2. **Play/pause is the bare transport glyph on every style**, Glass and Compact included, as in every Apple player. *Decided 2026-11-05 as part of Hum's Apple-native direction; this replaces the filled circle.* Media cards keep the floating accent play (family 6), which never uses Spotify green.
3. **Global shortcut defaults to ⌥⌘K**, with ⌘K inside Hum. *Retired 2026-11-07 with Find (§13.9). The Toggle Player shortcut keeps no default.*
4. **"Swipe to skip" is off by default.** Horizontal swipes move between surfaces.
5. **The accent marks state only.** The seek and volume fills stay neutral, as in Apple's player, rather than taking a colored fill as in Spotify.
6. **Throw-to-snap is on by default.** It works like picture-in-picture: the window settles at the nearest of the nine pin positions (§4.5, §13.10).
7. **Skip buttons scan when held**, where the source supports it (Music does; Spotify's app does not).
8. **Spotify-sourced artwork follows Spotify's guidelines.** *Superseded 2026-11-07 (§13.17): dropped.*
9. **Play and Find are removed; Status joins.** *Decided 2026-11-07: the library and search go, and a third surface after History shows which app Hum follows and whether Hum may control each one.* The surfaces are Now, Echo, Status (§6.3). Saved placements that remember Play or Find open on Now.
10. **Nine pin positions.** *Decided 2026-11-07: corners, the middle of each edge, and the center.* Throw-to-snap uses all nine (§4.5). Art Only at rest is the cover alone, with resting progress off by default (§7).
11. **Shuffle and repeat on every style**, on by default, Art Only and Text included (§5.2). Users who switched them off keep their choice.
12. **Glass, Data and Session are smaller**: 280 by default, 480 at most, Large 380 (§7), because they were all too big. *Superseded 2026-11-08 (§13.19): retired.*
13. **Menu bar.** *Decided 2026-11-07:* the item shows Hum's logo; the menu holds only the essentials (§5.8); the Menu Bar style shows the cover, title, play/pause and next, with a Now Playing popover and Pop Out Player (§7.1).
14. **Settings choices are visual tiles** (§8), more visual than a row of sliders. Buttons stay system push buttons and panes keep the toolbar title (§8). *Buttons amended 2026-11-09 (§13.27): they are Hum's action buttons.*
15. **No "Spotify" on the player or in its menus.** *Decided 2026-11-07 (§10).* `SourceBadge` is retired; "Show in Spotify" became "Show in App" for every source.
16. **Widgets for every display** (§7.3). Hum is built with the Command Line Tools, which lack Xcode's App Intents metadata tool, so widget buttons are links to Hum and small widgets have none. Building with Xcode later could switch them to App Intents buttons. *Amended 2026-11-09 (§13.33): only Art Only, Title and Text keep widgets.*
17. **One treatment for every cover.** *Decided 2026-11-07: Spotify's artwork rules are dropped.* Spotify covers get the scrim, the blurred backdrop, hover controls over the art, and the usual corners, like any other (§3.6).
18. **Liquid Glass only where macOS has it.** *Decided 2026-11-07: a Mac without Liquid Glass doesn't offer it.* On macOS 26, Appearance › Material offers Liquid Glass (default) or Frosted; on macOS 15 the row isn't shown and nothing imitates glass (§3.6.1).
19. **Glass, Data and Session are retired.** *Decided 2026-11-08: they wouldn't be chosen.* Six styles remain: Art Only, Title, Text, Strip, Big Art and Menu Bar (§7), with their widgets (§7.3). A saved `glass`, `data` or `session` style opens as Art Only, and their saved looks are dropped. Echo keeps its insights and session trail; only the styles that put them on Now go. Liquid Glass, the material, stays (§13.18).
20. **The song title is a step larger.** *Decided 2026-11-08, so the title stands apart.* `trackTitle` is 15 pt at S and M and 17 at L, `textTitle` 13, the Menu Bar popover's title 15, and the widgets follow (§3.3, §7.1, §7.3). The artist line is unchanged.
21. **The page indicator shows only when the page changes** (§6). *Decided 2026-11-08: the indicator marks a change rather than staying on screen.*
22. **Spotify's own icon where Hum shows the apps.** *Decided 2026-11-08.* Status and Settings › Sources show Spotify.app's icon from its bundle, as they show Music's (§3.5.7, §6.3, §8). The player, its menus and the widgets still don't identify the source (§13.15). Supersedes the 2026-11-05 rule.
23. **Echo is renamed History.** *Decided 2026-11-09.* The surfaces are Now, History, Status, everywhere a person reads them: the page indicator's tooltips, Show ▸, ⌘2, VoiceOver, Settings (History & Privacy), Help and the README. Code identifiers and stored values keep `echo`.
24. **Repeat one works with Spotify.** *Decided 2026-11-09: clicking repeat again repeats the song.* Spotify's app has only repeat on and off, so Hum starts the song again itself (§5.2). Off → All → One, with every source.
25. **The menu is narrower and has Listening History….** *Decided 2026-11-09.* The song is two truncated lines, so the menu is about 220 pt wide; Listening History… follows Show Player (§5.8).
26. **Settings never brings the Dock icon.** *Decided 2026-11-09: Settings is just settings, and only Listening History opens Hum as an app.* Only the Listening History window makes Hum a regular app with a Dock icon and main menu while it's open (§8). The standard About panel is retired for the Hum pane.
27. **Settings: the Hum pane, sections, and Hum's buttons.** *Decided 2026-11-09: About becomes a pane titled Hum that says a little about the app and its version, as in the other Line Apps; sections group the settings by purpose; and every Settings button takes the style Glow, Tuck and Pulse use.* The sidebar is grouped (General; Player: Appearance, Behavior, Shortcuts; Music: Sources, History & Privacy; Hum), every pane's sections have headers, and every Settings button is an action button (§5.9 family 9, §8). The Player pane is now Behavior, so "Player" names only the group.
28. **Hover controls leave the moment the pointer does.** *Decided 2026-11-09: they start to leave as soon as the pointer leaves the player.* The 0.8-s grace is gone; `Motion.conceal` (0.18 s) starts on exit and reverses if the pointer returns (§3.7, §4.1).
29. **Wide joins, and Big Art moves onto a card.** *Decided 2026-11-09, from a reference picture of a card with the cover on the left and the title, seek bar, transport and volume on the right: a new display outlined like Title, and Big Art outlined the same way with its controls under the cover, replacing the old Big Art.* Wide is a landscape card; Big Art keeps its name and stored value but is rebuilt as a portrait card with the controls under the cover; the edge-to-edge Big Art is deleted (§7). The name "Wide" is Hum's choice and easy to change.
30. **Widgets are on hold.** *Decided 2026-11-09: the widgets were broken, and they wait until the rest of the round is built.* This round changes nothing in the widgets beyond what compiling needs (§7.3). *Lifted the same day, once the build was done (§13.32).*
31. **The Listening History window.** *Decided 2026-11-09: no Playlists in Top unless both apps report playlists; no blue border around the whole calendar when it's clicked; menus in line with the Line Apps' buttons and design language; and the window opens with its sidebar collapsed, for more room.* Music reports a playlist but Spotify's app doesn't, so Top drops Playlists; the calendar has no whole-grid focus ring; the menus are pill menus; and the window opens with its sidebar collapsed (§6.5).
32. **The widgets are fixed.** *Decided 2026-11-09.* The widgets had frozen because the extension from an earlier build was still running: macOS turned down everything it drew ("Bundle version did not match"), so they kept the old song and the old look. Hum now retires such a process as it starts (§7.3). Wide gets a medium widget, and the Big Art widget is rebuilt on the card, as the player's Big Art was (§13.29). *Both went the same day (§13.33).*
33. **Three widgets.** *Decided 2026-11-09: Title, Art Only in both sizes, and the small Text widget stay, and the rest go.* Art Only keeps small and large, Title medium, and Text small only. The Text medium, Strip, Wide, Big Art and Menu Bar widgets are gone; those styles stay as displays (§7), without widgets. The three widgets keep their kinds, so ones already placed stay where they are (§7.3).
34. **Repeat's animation, Spotify's repeat one, and changes made in Spotify.** *Decided 2026-11-09: repeat one's animation was too slow and out of step with the controls beside it, repeat one didn't hold with Spotify, and shuffle and repeat changed in Spotify didn't show on the player.* Three fixes:
    - **The glyph.** Repeat's `repeat` ↔ `repeat.1` change cross-fades with the toggle's own spring, with the color and the dot, instead of the slower symbol replace (§3.4, §5.2).
    - **Repeat one.** Spotify answers a new position before it takes it, so a restart 1 s before the end could land after the song had ended, and the next song played. Hum now starts the song over about 2 s before the end, and a song that gives way to the next straight after a restart counts as ending, so Hum goes back to it (§5.2).
    - **Changes in Spotify.** Spotify posts nothing when shuffle or repeat changes, so Hum read them only every 20 s while playing and never while paused. Now, while Spotify is the frontmost app, Hum reads it every second, playing or paused; it reads it again when Spotify leaves the front and when the pointer enters the player. What Hum sets is held for a moment against Spotify's stale replies, so the player doesn't flick back (§4.6). Music gets the same.
35. **Repeat one stays Hum's own, and says so once.** *Decided 2026-11-09.* Repeating the playlist worked with Spotify, but repeating one song seemed not to. Hum's log showed every press reaching Spotify, and a song Hum started over 1.4 s before its end. What hadn't changed was Spotify's own repeat button, which Hum can only turn on or off. Making Spotify's window show repeat one would mean pressing Spotify's own Repeat through Accessibility, a new permission outside its AppleScript dictionary (§1.3). Hum keeps its own restart, with a note the first time One is picked (§5.2).
