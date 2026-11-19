import CoreGraphics
import Foundation

/// The finished demo art: each scene with its colors, its composition, and the
/// film it was "shot" on. Everything is chosen from a seed, so the same name
/// always gets the same picture.
enum CoverArt {
    // MARK: The player's covers

    /// Each cover suits its song: "Low Tide Radio" is a pale morning sea,
    /// "Lantern Arithmetic" the lights of a street at night, "Switchback Hymn"
    /// a mountain dusk, "Glasshouse Weather" a conservatory through fogged
    /// glass, "Neon Ledger" a figure at a window over a neon street, and
    /// "Monochrome Letters" type on paper. The history's singles get their
    /// own: "Northbound" aurora green over polar ice, and "Paper Boats" its
    /// title.
    static func paint(_ cover: DemoCover, on canvas: ArtCanvas) {
        switch cover {
        case .tide:
            sea(Sea.palettes[0], sun: (0.6, 0.76), horizon: 0.64, headland: 1, seed: 11, on: canvas)
        case .lanterns:
            bokeh(Bokeh.palettes[0], count: 90, seed: 23, on: canvas)
        case .ridges:
            dusk(Dusk.palettes[0], sun: (0.64, 0.46), horizon: 0.44, clouds: 0.5, seed: 7, on: canvas)
        case .glasshouse:
            mesh(Mesh.palettes[0], leaves: 1, jitter: 0, seed: 41, on: canvas)
        case .ledger:
            let figure = ArtFigure(x: 0.4, y: 0.58, head: 0.078, shoulders: 0.26, hair: .cropped, tilt: -0.1, turn: 0.5, seed: 31)
            window(Window.palettes[0], figure: figure, seed: 31, on: canvas)
        case .rings:
            type(TypeCover(title: "Ash & Paper", byline: "Hollis Weather", mark: "HW 03", paper: ArtColor(0xE9E3D6), ink: ArtColor(0x1C1A18), face: .serif, layout: .stacked, seed: 61), on: canvas)
        case .floes:
            field(Field(ground: ArtColor(0x101C26), colors: [ArtColor(0x3FAF86), ArtColor(0xD3E2E6)]), seed: 83, on: canvas)
        case .folded:
            type(TypeCover(title: "Paper Boats", byline: "Wren Okoye", mark: "WO 01", paper: ArtColor(0xD6E2E8), ink: ArtColor(0x1F4A8A), face: .sans, layout: .centered, seed: 97), on: canvas)
        }
    }

    // MARK: Library albums

    enum Style: CaseIterable {
        case dusk, sea, bokeh, window, mesh, field, type
    }

    /// The style an album title suggests: water for rivers and harbors, city
    /// lights for signals and stations, type for letters, and so on. Titles
    /// that suggest nothing get a style from the seed.
    static func style(forTitle title: String, seed: UInt64) -> Style {
        var random = ArtRandom(seed: seed ^ 0x5717)
        switch title.split(separator: " ").last?.lowercased() ?? "" {
        case "rivers", "tides", "harbors": return .sea
        case "signals", "stations", "satellites", "engines", "lanterns", "fires": return .bokeh
        case "letters", "postcards": return .type
        case "rooms", "windows", "mirrors": return random.chance(0.6) ? .window : .field
        case "weather", "orchards": return .dusk
        case "gardens": return .mesh
        case "bridges": return random.chance(0.5) ? .field : .dusk
        default: return random.pick(Style.allCases)
        }
    }

    /// An album cover for a title and artist. The first word of the title
    /// picks the colors, so "Golden Rivers" and "Golden Rooms" belong together.
    static func paintAlbum(title: String, artist: String, seed: UInt64, on canvas: ArtCanvas) {
        var random = ArtRandom(seed: seed)
        let mood = ArtRandom.seed(title.split(separator: " ").first.map(String.init)?.lowercased() ?? title)
        // The first palette of each scene belongs to the player's own cover;
        // library albums use the others, so no album repeats a starting song.
        func palette<T>(_ palettes: [T], skippingFirst: Bool = true) -> T {
            let choices = skippingFirst ? Array(palettes.dropFirst()) : palettes
            return choices[Int(mood % UInt64(choices.count))]
        }
        switch style(forTitle: title, seed: seed) {
        case .dusk:
            dusk(
                palette(Dusk.palettes),
                sun: (random.range(0.25...0.75), random.range(0.42...0.58)),
                horizon: random.range(0.4...0.5),
                clouds: random.range(0.2...0.8),
                seed: seed,
                on: canvas
            )
        case .sea:
            sea(
                palette(Sea.palettes),
                sun: (random.range(0.3...0.7), random.range(0.7...0.86)),
                horizon: random.range(0.56...0.68),
                headland: random.chance(0.6) ? 1 : 0,
                seed: seed,
                on: canvas
            )
        case .bokeh:
            bokeh(palette(Bokeh.palettes), count: 60 + random.below(50), seed: seed, on: canvas)
        case .window:
            var look = palette(Window.palettes)
            look.neon = look.neon.map { ($0.color, $0.x + random.range(-0.12...0.08), $0.y + random.range(-0.12...0.12), $0.radius * random.range(0.8...1.2)) }
            let frame = CGRect(x: random.range(0.28...0.42), y: random.range(0.1...0.2), width: 0.74, height: 0.92)
            let figure = ArtFigure(
                x: random.range(0.36...0.5),
                y: random.range(0.52...0.6),
                head: random.range(0.07...0.09),
                shoulders: random.range(0.23...0.28),
                hair: random.pick(ArtFigure.Hair.allCases),
                tilt: random.range(-0.15...0.15),
                turn: random.range(-0.6...0.6),
                seed: seed
            )
            window(look, figure: figure, frame: frame, seed: seed, on: canvas)
        case .mesh:
            mesh(palette(Mesh.palettes), leaves: random.chance(0.4) ? 1 : 0, jitter: 0.12, seed: seed, on: canvas)
        case .field:
            var look = palette(Field.palettes, skippingFirst: false)
            look.colors.shuffle(using: &random)
            field(look, seed: seed, on: canvas)
        case .type:
            let look = palette(Paper.palettes, skippingFirst: false)
            let initials = artist.split(separator: " ").compactMap(\.first).map(String.init).joined()
            type(TypeCover(
                title: title,
                byline: artist,
                mark: "\(initials) \(String(format: "%02d", 1 + random.below(30)))",
                paper: look.paper,
                ink: look.ink,
                face: look.face,
                layout: look.layout,
                seed: seed
            ), on: canvas)
        }
        // Every album was shot on a slightly different stock: a small,
        // seeded shift of white balance keeps albums of one style apart.
        let warmth = random.range(-0.14...0.14)
        canvas.tone(red: ToneCurve(gamma: 1 + warmth), green: .identity, blue: ToneCurve(gamma: 1 - warmth))
    }

    // MARK: Artists

    /// A press photo for an artist, never a real face: a figure lit from
    /// behind, from above, or from a window, the face always in shadow. Bands
    /// get the stage instead, in lights.
    static func paintPortrait(seed: UInt64, band: Bool, on canvas: ArtCanvas) {
        var random = ArtRandom(seed: seed)
        if band {
            var stage = random.pick(Array(Bokeh.palettes.dropFirst()))
            stage.night = [(stage.night[0].0, 0), (stage.night[1].0, 0.5), (stage.night[2].0.scaled(0.6), 1)]
            bokeh(stage, count: 50 + random.below(30), band: 0.45...0.95, seed: seed, on: canvas)
            return
        }
        let look = random.pick(Portrait.palettes)
        let light = random.pick(StudioPortrait.Light.allCases)
        // Profiles suit window light; the others look toward the camera more.
        let turn = light == .window ? random.pick([-1.0, 1.0]) * random.range(0.85...1) : random.range(-0.7...0.7)
        let figure = ArtFigure(
            x: random.range(0.45...0.55),
            y: random.range(0.5...0.56),
            head: random.range(0.1...0.14),
            shoulders: random.range(0.3...0.4),
            hair: light == .spot ? random.pick([ArtFigure.Hair.long, .cropped, .bun]) : random.pick(ArtFigure.Hair.allCases),
            tilt: random.range(-0.2...0.2),
            turn: turn,
            seed: seed
        )
        StudioPortrait(backdrop: look.backdrop, lamp: look.lamp, light: light, figure: figure, seed: seed).paint(canvas)
        var finish = ArtFinish.film(black: 0.04, white: 0.97, contrast: 0.12)
        finish.bloom = (0.7, 0.03, 0.4)
        finish.vignette = 0.3
        finish.grain = 0.14
        finish.clump = 1.3
        finish.apply(canvas, seed: seed)
    }

    // MARK: Playlists

    /// A playlist cover: the name set over a picture that suits it, the way an
    /// editor's playlists look, with the curator's name above.
    static func paintPlaylist(name: String, owner: String?, seed: UInt64, on canvas: ArtCanvas) {
        var random = ArtRandom(seed: seed)
        let words = Set(name.lowercased().split(separator: " ").map(String.init))
        let sunX = random.range(0.3...0.7)
        let picture: (ArtCanvas) -> Void
        if !words.isDisjoint(with: ["swim", "rainy", "focus", "drive"]) {
            let look = random.pick(Array(Sea.palettes.dropFirst()))
            picture = { sea(look, sun: (sunX, 0.8), horizon: 0.66, headland: 1, seed: seed, on: $0, finish: false) }
        } else if !words.isDisjoint(with: ["burn", "late", "night", "dancing"]) {
            let look = random.pick(Array(Bokeh.palettes.dropFirst()))
            picture = { bokeh(look, count: 80, seed: seed, on: $0, finish: false) }
        } else if !words.isDisjoint(with: ["sunday", "morning", "home"]) {
            let look = random.pick(Array(Dusk.palettes.dropFirst()))
            picture = { dusk(look, sun: (sunX, 0.5), horizon: 0.42, clouds: 0.5, seed: seed, on: $0, finish: false) }
        } else {
            let look = random.pick(Array(Mesh.palettes.dropFirst()))
            picture = { mesh(look, leaves: 0, jitter: 0.12, seed: seed, on: $0, finish: false) }
        }
        TypeCover(title: name, byline: owner ?? "", paper: ArtColor(0x1A2030), ink: .white, face: .sans, layout: .corner, seed: seed)
            .paint(canvas, picture: picture)
        var finish = ArtFinish.film(black: 0.03, white: 0.98, contrast: 0.1)
        finish.vignette = 0.2
        finish.grain = 0.09
        finish.apply(canvas, seed: seed)
    }

    // MARK: Scenes with their finishes

    struct Dusk {
        var sky: [(ArtColor, Double)]
        var sun: ArtColor
        var far: ArtColor
        var near: ArtColor
        var mist: ArtColor

        static let palettes = [
            // Rose dusk.
            Dusk(sky: [(ArtColor(0xF6A872), 0.38), (ArtColor(0xE07C7A), 0.55), (ArtColor(0x8A5F98), 0.75), (ArtColor(0x353F78), 1)], sun: ArtColor(0xFFC27A), far: ArtColor(0xCC8F96), near: ArtColor(0x1E1830), mist: ArtColor(0xEDA88E)),
            // Blue hour.
            Dusk(sky: [(ArtColor(0xA9BCD0), 0.38), (ArtColor(0x7D93B2), 0.55), (ArtColor(0x4D5F86), 0.75), (ArtColor(0x222B4A), 1)], sun: ArtColor(0xF4E3C8), far: ArtColor(0x8094AE), near: ArtColor(0x111827), mist: ArtColor(0xB8C6D6)),
            // Golden haze.
            Dusk(sky: [(ArtColor(0xF6D58E), 0.38), (ArtColor(0xEDB46E), 0.55), (ArtColor(0xC98A62), 0.75), (ArtColor(0x6E5A6E), 1)], sun: ArtColor(0xFFE7A8), far: ArtColor(0xC7976A), near: ArtColor(0x2B2119), mist: ArtColor(0xF2D29C)),
            // A green, misty morning.
            Dusk(sky: [(ArtColor(0xDCE3D2), 0.38), (ArtColor(0xB9C7B9), 0.55), (ArtColor(0x8FA3A0), 0.75), (ArtColor(0x56676E), 1)], sun: ArtColor(0xFFF6DE), far: ArtColor(0x9CAC9A), near: ArtColor(0x1E2A24), mist: ArtColor(0xE2E8DA)),
        ]
    }

    static func dusk(_ look: Dusk, sun: (Double, Double), horizon: Double, clouds: Double, seed: UInt64, on canvas: ArtCanvas, finish: Bool = true) {
        DuskLandscape(sky: look.sky, sun: sun, sunColor: look.sun, far: look.far, near: look.near, mist: look.mist, horizon: horizon, clouds: clouds, seed: seed)
            .paint(canvas)
        guard finish else { return }
        var film = ArtFinish.film(black: 0.05, white: 0.97, contrast: 0.2)
        film.soften = 0.0015
        film.bloom = (0.72, 0.03, 0.5)
        film.vignette = 0.28
        film.grain = 0.1
        film.clump = 1.3
        film.apply(canvas, seed: seed)
    }

    struct Sea {
        var sky: [(ArtColor, Double)]
        var sun: ArtColor
        var deep: ArtColor
        var shallow: ArtColor

        static let palettes = [
            // A pale, pearly morning.
            Sea(sky: [(ArtColor(0xF59E62), 0), (ArtColor(0xF0A880), 0.45), (ArtColor(0x7E98C8), 1)], sun: ArtColor(0xFFD49A), deep: ArtColor(0x004A62), shallow: ArtColor(0x0E7C94)),
            // Sundown over a violet sea.
            Sea(sky: [(ArtColor(0xF1B27A), 0), (ArtColor(0xD7848A), 0.4), (ArtColor(0x5B4D7A), 1)], sun: ArtColor(0xFFC27A), deep: ArtColor(0x1E1B33), shallow: ArtColor(0x4A3A5C)),
            // A cold, clear noon.
            Sea(sky: [(ArtColor(0xD9E6EE), 0), (ArtColor(0xA9C4DA), 0.4), (ArtColor(0x5E86AE), 1)], sun: ArtColor(0xFFFFFF), deep: ArtColor(0x0F2F48), shallow: ArtColor(0x2D6A8A)),
            // Overcast, gray-green, before rain.
            Sea(sky: [(ArtColor(0xC2CABC), 0), (ArtColor(0x97A49E), 0.4), (ArtColor(0x55626A), 1)], sun: ArtColor(0xF2F0E0), deep: ArtColor(0x1A2E2C), shallow: ArtColor(0x3A5A52)),
        ]
    }

    static func sea(_ look: Sea, sun: (Double, Double), horizon: Double, headland: Double, seed: UInt64, on canvas: ArtCanvas, finish: Bool = true) {
        SeaGlitter(sky: look.sky, sun: sun, sunColor: look.sun, deep: look.deep, shallow: look.shallow, horizon: horizon, headland: headland, seed: seed)
            .paint(canvas)
        guard finish else { return }
        var film = ArtFinish.film(black: 0.05, white: 0.97, contrast: 0.2)
        film.bloom = (0.7, 0.02, 0.6)
        film.vignette = 0.25
        film.grain = 0.1
        film.clump = 1.3
        film.apply(canvas, seed: seed)
    }

    struct Bokeh {
        var night: [(ArtColor, Double)]
        var lights: [(ArtColor, Double)]
        var halation: ArtColor

        static let palettes = [
            // Sodium and tungsten: a warm street at night.
            Bokeh(night: [(ArtColor(0x0B0C12), 0), (ArtColor(0x141826), 0.6), (ArtColor(0x0A0B10), 1)], lights: [(ArtColor(0xFFA84A), 5), (ArtColor(0xFF7A2E), 3), (ArtColor(0xE8433A), 1.5), (ArtColor(0xFFE2B0), 1.5), (ArtColor(0x9FD6DA), 0.3)], halation: ArtColor(0xFF5A2A)),
            // Cold LED blue and white, a little red.
            Bokeh(night: [(ArtColor(0x06080E), 0), (ArtColor(0x0E1626), 0.6), (ArtColor(0x05070C), 1)], lights: [(ArtColor(0x9FD6FF), 4), (ArtColor(0xFFFFFF), 2), (ArtColor(0x6FA8FF), 2), (ArtColor(0xFF5A7A), 1)], halation: ArtColor(0x5A8CFF)),
            // Rain on a window: teal signs and amber headlights.
            Bokeh(night: [(ArtColor(0x081012), 0), (ArtColor(0x0E1C20), 0.6), (ArtColor(0x060A0C), 1)], lights: [(ArtColor(0x4FD1C5), 3), (ArtColor(0xFFB347), 3), (ArtColor(0xFFFFFF), 1), (ArtColor(0xFF6B6B), 1)], halation: ArtColor(0x2AA198)),
            // Festival reds and golds, a few greens.
            Bokeh(night: [(ArtColor(0x100A0C), 0), (ArtColor(0x1E1218), 0.6), (ArtColor(0x0C0809), 1)], lights: [(ArtColor(0xFF4A3A), 3), (ArtColor(0xFFB04A), 3), (ArtColor(0x7CE08A), 1.2), (ArtColor(0xFFF0C8), 1)], halation: ArtColor(0xFF3A2A)),
        ]
    }

    static func bokeh(_ look: Bokeh, count: Int, band: ClosedRange<Double> = 0.25...0.72, seed: UInt64, on canvas: ArtCanvas, finish: Bool = true) {
        CityBokeh(night: look.night, lights: look.lights, count: count, band: band, halation: look.halation, seed: seed).paint(canvas)
        guard finish else { return }
        var film = ArtFinish()
        film.red = ToneCurve(black: 0.05, white: 0.98, contrast: 0.1)
        film.green = ToneCurve(black: 0.07, white: 0.95, contrast: 0.1)
        film.blue = ToneCurve(black: 0.08, white: 0.88, contrast: 0.1)
        film.vignette = 0.3
        film.grain = 0.22
        film.clump = 1.5
        film.apply(canvas, seed: seed)
    }

    struct Window {
        var room: ArtColor
        var neon: [(color: ArtColor, x: Double, y: Double, radius: Double)]
        var outside: [(ArtColor, Double)]

        static let palettes = [
            // Pink and cyan neon.
            Window(room: ArtColor(0x0C0A10), neon: [(ArtColor(0xFF3D8E), 0.82, 0.74, 0.42), (ArtColor(0x2FC6E8), 0.6, 0.38, 0.3), (ArtColor(0xFFB24A), 0.98, 0.3, 0.16)], outside: [(ArtColor(0x120F2A), 0), (ArtColor(0x231A40), 1)]),
            // Amber signs and a red awning.
            Window(room: ArtColor(0x0C0908), neon: [(ArtColor(0xFFA040), 0.8, 0.7, 0.4), (ArtColor(0xFF5A3A), 0.6, 0.35, 0.3), (ArtColor(0xFFE0A0), 0.95, 0.3, 0.15)], outside: [(ArtColor(0x1A100A), 0), (ArtColor(0x2A1A10), 1)]),
            // Blue and violet.
            Window(room: ArtColor(0x090B12), neon: [(ArtColor(0x3A7BFF), 0.82, 0.74, 0.42), (ArtColor(0x7AE0FF), 0.6, 0.38, 0.3), (ArtColor(0xC07AFF), 0.98, 0.3, 0.16)], outside: [(ArtColor(0x0A1026), 0), (ArtColor(0x16204A), 1)]),
        ]
    }

    static func window(_ look: Window, figure: ArtFigure, frame: CGRect = CGRect(x: 0.34, y: 0.16, width: 0.74, height: 0.92), seed: UInt64, on canvas: ArtCanvas) {
        WindowLight(room: look.room, neon: look.neon, outside: look.outside, window: frame, figure: figure, seed: seed).paint(canvas)
        var film = ArtFinish()
        film.bloom = (0.55, 0.03, 0.5)
        film.red = ToneCurve(black: 0.05, white: 0.98, contrast: 0.15)
        film.green = ToneCurve(black: 0.06, white: 0.94, contrast: 0.15)
        film.blue = ToneCurve(black: 0.09, white: 0.96, contrast: 0.15)
        film.vignette = 0.35
        film.grain = 0.2
        film.clump = 1.5
        film.apply(canvas, seed: seed)
    }

    struct Mesh {
        var points: [(color: ArtColor, x: Double, y: Double, reach: Double)]

        static let palettes = [
            // Conservatory greens, blossom, and warm light.
            Mesh(points: [(ArtColor(0xF0E6D2), 0.5, 0.85, 0.35), (ArtColor(0x6AAA7E), 0.15, 0.55, 0.3), (ArtColor(0xF295AA), 0.72, 0.5, 0.25), (ArtColor(0x245A40), 0.25, 0.12, 0.3), (ArtColor(0xF5C470), 0.85, 0.85, 0.2), (ArtColor(0xE0624E), 0.62, 0.22, 0.2)]),
            // Peach into violet.
            Mesh(points: [(ArtColor(0xFFD3A8), 0.2, 0.8, 0.35), (ArtColor(0xFF8F7A), 0.75, 0.75, 0.3), (ArtColor(0x9B6FBF), 0.6, 0.2, 0.3), (ArtColor(0x3E3A7A), 0.15, 0.15, 0.3), (ArtColor(0xFFB6C8), 0.45, 0.5, 0.25)]),
            // Sea glass.
            Mesh(points: [(ArtColor(0xCFEDE6), 0.3, 0.8, 0.35), (ArtColor(0x5FB8B0), 0.8, 0.6, 0.3), (ArtColor(0x1F5A6E), 0.3, 0.2, 0.3), (ArtColor(0xE8F0D8), 0.85, 0.9, 0.2), (ArtColor(0x88A8D8), 0.6, 0.3, 0.25)]),
        ]
    }

    static func mesh(_ look: Mesh, leaves: Double, jitter: Double, seed: UInt64, on canvas: ArtCanvas, finish: Bool = true) {
        var random = ArtRandom(seed: seed ^ 0x3E54)
        let points: [(color: ArtColor, x: Double, y: Double, reach: Double)] = look.points.map { point in
            (point.color, point.x + random.range(-jitter...jitter), point.y + random.range(-jitter...jitter), point.reach)
        }
        SoftMesh(points: points, leaves: leaves, seed: seed).paint(canvas)
        guard finish else { return }
        var film = ArtFinish.film(black: 0.04, white: 0.98, contrast: 0.1)
        film.vignette = 0.12
        film.grain = 0.12
        film.clump = 1.2
        film.apply(canvas, seed: seed)
    }

    struct Field {
        var ground: ArtColor
        var colors: [ArtColor]

        static let palettes = [
            Field(ground: ArtColor(0x8E2F25), colors: [ArtColor(0xD9572E), ArtColor(0x3A1A1C), ArtColor(0xE89A4A)]),
            Field(ground: ArtColor(0x23345A), colors: [ArtColor(0x6A8CC8), ArtColor(0x101A30), ArtColor(0xC8D2E0)]),
            Field(ground: ArtColor(0xB8913A), colors: [ArtColor(0xE8C25A), ArtColor(0x3E4A2A), ArtColor(0x8A3A22)]),
        ]
    }

    static func field(_ look: Field, seed: UInt64, on canvas: ArtCanvas) {
        var random = ArtRandom(seed: seed ^ 0xF1E1)
        // Two or three stacked fields with a margin of ground around them.
        let count = random.chance(0.6) ? 2 : 3
        let margin = random.range(0.08...0.12)
        let gap = random.range(0.05...0.09)
        var heights = (0..<count).map { _ in random.range(0.6...1.4) }
        let scale = (1 - margin * 2 - gap * Double(count - 1)) / heights.reduce(0, +)
        heights = heights.map { $0 * scale }
        var y = 1 - margin
        var fields: [(color: ArtColor, frame: CGRect)] = []
        for (index, height) in heights.enumerated() {
            y -= height
            fields.append((look.colors[index % look.colors.count], CGRect(x: margin, y: y, width: 1 - margin * 2, height: height)))
            y -= gap
        }
        ColorFieldPainting(ground: look.ground, fields: fields, seed: seed).paint(canvas)
        var film = ArtFinish.film(black: 0.03, white: 0.98, contrast: 0.08)
        film.vignette = 0.18
        film.grain = 0.08
        film.apply(canvas, seed: seed)
    }

    struct Paper {
        var paper: ArtColor
        var ink: ArtColor
        var face: TypeCover.Face
        var layout: TypeCover.Layout

        static let palettes = [
            Paper(paper: ArtColor(0xE9E3D6), ink: ArtColor(0x1C1A18), face: .serif, layout: .stacked),
            Paper(paper: ArtColor(0x1E2A4A), ink: ArtColor(0xF0C35A), face: .sans, layout: .centered),
            Paper(paper: ArtColor(0xEFEBE3), ink: ArtColor(0xC8342A), face: .sans, layout: .centered),
            Paper(paper: ArtColor(0x161514), ink: ArtColor(0xEDE8DE), face: .serif, layout: .stacked),
        ]
    }

    static func type(_ cover: TypeCover, on canvas: ArtCanvas) {
        cover.paint(canvas)
        var film = ArtFinish.film(black: 0.02, white: 0.99, contrast: 0.05)
        film.vignette = cover.paper.luma > 0.5 ? 0.1 : 0.2
        film.grain = 0.07
        film.apply(canvas, seed: cover.seed)
    }

    struct Portrait {
        var backdrop: ArtColor
        var lamp: ArtColor

        static let palettes = [
            Portrait(backdrop: ArtColor(0x6C5A8C), lamp: ArtColor(0xFFB98A)),
            Portrait(backdrop: ArtColor(0x2A3E6C), lamp: ArtColor(0xBFD8FF)),
            Portrait(backdrop: ArtColor(0x8C7A66), lamp: ArtColor(0xFFE2B8)),
            Portrait(backdrop: ArtColor(0x3E6A5E), lamp: ArtColor(0xFFE9C2)),
            Portrait(backdrop: ArtColor(0x8A3E3A), lamp: ArtColor(0xFFC48A)),
            Portrait(backdrop: ArtColor(0x4A4A50), lamp: ArtColor(0xF2F2F2)),
        ]
    }
}
