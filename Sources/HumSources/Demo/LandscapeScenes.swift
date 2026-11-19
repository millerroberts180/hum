import CoreGraphics
import Foundation

/// A hazy photograph of hills at dusk: ridges fading into the sky one behind
/// another, mist in the valleys, and the low sun blooming through the haze.
struct DuskLandscape {
    /// The sky from the bottom of the frame (0) to the top (1).
    var sky: [(ArtColor, Double)]
    var sun: (x: Double, y: Double)
    var sunColor: ArtColor
    /// The farthest ridge, almost the color of the sky behind it.
    var far: ArtColor
    /// The nearest ridge.
    var near: ArtColor
    /// The mist that collects in the valleys.
    var mist: ArtColor
    var layers = 6
    /// Where the farthest ridge sits.
    var horizon = 0.44
    /// Wisps of cloud, 0 for a clear sky.
    var clouds = 0.5
    var seed: UInt64

    func paint(_ canvas: ArtCanvas) {
        let noise = ValueNoise(seed: seed)
        canvas.linearGradient(sky, from: (0.5, 0), to: (0.5, 1))

        // Long wisps of cloud, lit from below where they near the sun.
        if clouds > 0 {
            let lit = sunColor.mixed(with: ArtColor.ramp(sky, 0.7), 0.35)
            let wisps = ArtField.gray(width: 128, height: 128) { u, v in
                let warp = noise.fractal(u * 3 + 11, v * 3, octaves: 3) - 0.5
                let n = noise.fractal(u * 1.8 + warp * 1.2 + 3.1, v * 9 + warp * 2.5, octaves: 5)
                let band = smoothstep(horizon + 0.02, horizon + 0.16, v) * (1 - smoothstep(0.72, 1, v))
                let nearSun = 1 - smoothstep(0, 0.6, abs(u - sun.x)) * 0.5
                return smoothstep(0.5, 0.78, n) * band * nearSun
            }
            canvas.fill(lit, through: wisps, alpha: 0.5 * clouds)
        }

        // The sun, low and diffused, with a wide halo of scattered light.
        canvas.layer(.screen) {
            canvas.glow(sunColor, at: (sun.x, sun.y), radius: 0.75, alpha: 0.45)
            canvas.glow(sunColor, at: (sun.x, sun.y), radius: 0.24, alpha: 0.6)
            canvas.glow(sunColor.mixed(with: .white, 0.55), at: (sun.x, sun.y), radius: 0.06, alpha: 1, hardness: 0.3)
        }
        canvas.blur(0.004)

        var random = ArtRandom(seed: seed)
        for layer in 0..<layers {
            let depth = Double(layer) / Double(max(1, layers - 1))
            // Farther ridges crowd together toward the horizon, as in perspective.
            let base = horizon - (horizon - 0.1) * pow(depth, 1.35) + random.range(-0.015...0.015)
            let amplitude = 0.045 + 0.06 * depth
            // Far ranges show many small peaks; the nearest hill is one broad shape.
            let frequency = 3.2 - 1.9 * depth
            let offset = random.range(0...40)
            let color = far.mixed(with: near, pow(depth, 1.1))
            let crest: (Double) -> Double = { x in
                let smooth = noise.fractal(x * frequency + offset, Double(layer) * 7.7, octaves: 6, gain: 0.5)
                // Folded noise makes sharper peaks and rounder saddles.
                let ridged = 1 - abs(noise.fractal(x * frequency * 0.7 + offset * 1.3, Double(layer) * 3.1, octaves: 4) * 2 - 1)
                return base + amplitude * ((smooth - 0.5) * 2.2 + (ridged - 0.6) * 0.9)
            }

            let ridge = CGMutablePath()
            ridge.move(to: canvas.point(0, 0))
            // The two nearest ridges are forested: rows of small pointed conifers.
            let trees = layers - layer <= 2
            let treeHeight = layer == layers - 1 ? 0.03 : 0.014
            var x = 0.0
            while x <= 1 {
                if trees {
                    // Stands of trees with gaps between them, every tree a different height.
                    let stand = smoothstep(0.3, 0.6, noise.value(x * 14 + offset, 1.5))
                    let width = treeHeight * random.range(0.22...0.55)
                    let height = treeHeight * random.range(0.3...1) * (0.15 + 0.85 * stand)
                    let ground = crest(x)
                    let lean = random.range(-0.15...0.15) * width
                    ridge.addLine(to: canvas.point(x, ground + height * 0.15))
                    ridge.addLine(to: canvas.point(x + width * 0.3, ground + height * 0.55))
                    ridge.addLine(to: canvas.point(x + width * 0.5 + lean, ground + height))
                    ridge.addLine(to: canvas.point(x + width * 0.7, ground + height * 0.5))
                    ridge.addLine(to: canvas.point(x + width, crest(x + width) + height * 0.1))
                    x += width * random.range(0.45...1)
                } else {
                    ridge.addLine(to: canvas.point(x, crest(x)))
                    x += 1.0 / 200
                }
            }
            ridge.addLine(to: canvas.point(1, crest(1)))
            ridge.addLine(to: canvas.point(1, 0))
            ridge.closeSubpath()

            canvas.context.saveGState()
            canvas.context.addPath(ridge)
            canvas.context.clip()
            // Lighter along the crest where the sky shows through, misty at the foot.
            canvas.linearGradient(
                [(color.mixed(with: mist, 0.55 - 0.35 * depth), 0), (color, 0.75), (color.mixed(with: far, 0.12), 1)],
                from: (0.5, base - amplitude * 2.2),
                to: (0.5, base + amplitude)
            )
            // The mottle of forest on the slopes, stronger on nearer ridges.
            let mottle = ArtField.gray(width: 128, height: 48) { u, v in
                noise.fractal(u * 26 + offset, v * 9 + Double(layer) * 5, octaves: 3)
            }
            canvas.draw(mottle, in: CGRect(x: 0, y: base - 0.2, width: 1, height: 0.2 + amplitude * 1.5), blend: .overlay, alpha: 0.08 + 0.22 * depth)
            canvas.context.restoreGState()

            // Fog drifting in the valley in front of this ridge.
            if layer < layers - 1 {
                let top = base - amplitude * 0.2
                let bottom = top - 0.12
                let fog = ArtField.gray(width: 96, height: 24) { u, v in
                    let n = noise.fractal(u * 3 + offset, v * 2.5 + Double(layer), octaves: 4)
                    return smoothstep(0.35, 0.75, n) * smoothstep(0, 0.6, v) * (1 - smoothstep(0.7, 1, v))
                }
                canvas.fill(mist, through: fog, in: CGRect(x: 0, y: bottom, width: 1, height: top - bottom), alpha: 0.35 * (1 - depth * 0.6))
                // Everything farther away softens a little more.
                canvas.blur(0.0018)
            }
        }

        // Light wrapping over the ridges nearest the sun.
        canvas.layer(.screen) {
            canvas.glow(sunColor, at: (sun.x, sun.y), radius: 0.5, alpha: 0.28)
        }
    }
}

/// The finishing pass that makes a painted scene read as a photograph or a
/// print: lens bloom, a film tone curve, vignetting, and grain.
struct ArtFinish {
    var bloom: (threshold: Double, radius: Double, strength: Double)?
    var red = ToneCurve.identity
    var green = ToneCurve.identity
    var blue = ToneCurve.identity
    var vignette = 0.0
    var grain = 0.0
    var clump = 1.0
    /// A last overall softening, as from a lens slightly out of focus.
    var soften = 0.0

    /// Matte film: blacks lifted to `black`, whites held under `white`.
    static func film(black: Double, white: Double = 0.97, contrast: Double = 0.15) -> ArtFinish {
        var finish = ArtFinish()
        let curve = ToneCurve(black: black, white: white, contrast: contrast)
        finish.red = curve
        finish.green = curve
        finish.blue = curve
        return finish
    }

    func apply(_ canvas: ArtCanvas, seed: UInt64) {
        if soften > 0 { canvas.blur(soften) }
        if let bloom { canvas.bloom(threshold: bloom.threshold, radius: bloom.radius, strength: bloom.strength) }
        canvas.tone(red: red, green: green, blue: blue)
        if vignette > 0 { canvas.vignette(vignette) }
        if grain > 0 { canvas.grain(grain, clump: clump, seed: seed) }
    }
}

/// A photograph of open sea in low sun: waves shrinking toward a hazy horizon,
/// a path of glitter under the sun, and a far headland.
struct SeaGlitter {
    /// The sky from the horizon (0) to the top of the frame (1).
    var sky: [(ArtColor, Double)]
    var sun: (x: Double, y: Double)
    var sunColor: ArtColor
    /// The water nearest the camera, and the water near the horizon where it
    /// mirrors the sky.
    var deep: ArtColor
    var shallow: ArtColor
    var horizon = 0.64
    /// A low line of land on the horizon, 0 for none.
    var headland = 1.0
    var seed: UInt64

    func paint(_ canvas: ArtCanvas) {
        let noise = ValueNoise(seed: seed)
        let horizon = horizon
        canvas.linearGradient(
            sky.map { ($0.0, horizon + $0.1 * (1 - horizon)) },
            from: (0.5, 0),
            to: (0.5, 1)
        )
        canvas.layer(.screen) {
            canvas.glow(sunColor, at: (sun.x, sun.y), radius: 0.6, alpha: 0.35)
            canvas.glow(sunColor.mixed(with: .white, 0.5), at: (sun.x, sun.y), radius: 0.07, alpha: 0.9, hardness: 0.2)
        }

        // Water: waves in perspective, compressed toward the horizon, mirroring
        // more of the sky the farther they are.
        let reflection = ArtColor.ramp(sky, 0.15)
        let water = ArtField.color(width: 240, height: Int(240 * horizon)) { u, v in
            // How far below the horizon this row sits, in frame heights.
            let distance = max(0.002, (1 - v) * horizon)
            let depth = 0.18 / (distance + 0.012)
            let x = (u - 0.5) * depth * 1.6
            let z = depth * 5.5
            // Fewer octaves far away, so tiny waves don't flicker into noise.
            let detail = distance > 0.15 ? 5 : (distance > 0.05 ? 4 : 3)
            let wave = noise.fractal(x + 20, z, octaves: detail, gain: 0.55)
            let swell = noise.fractal(x * 0.25 + 5, z * 0.3, octaves: 2)
            let fresnel = pow(1 - min(1, distance / 0.55), 2.2)
            var color = deep.mixed(with: shallow, swell * 0.5)
            // Close to the camera, troughs fall into shadow and crests catch the sky.
            color = color.scaled(0.72 + wave * 0.6 * (1 - fresnel))
            color = color.mixed(with: reflection, min(1, fresnel * 0.9 + (wave - 0.45) * 0.6 * (0.4 + fresnel)))
            // Wave faces tilted toward the sun pick up its color.
            let facing = smoothstep(0.55, 0.8, wave) * (1 - smoothstep(0, 0.4 + distance * 0.6, abs(u - sun.x)))
            return color.mixed(with: sunColor, facing * 0.35)
        }
        canvas.draw(water, in: CGRect(x: 0, y: 0, width: 1, height: horizon))

        // A far headland, softened by haze.
        if headland > 0 {
            let land = CGMutablePath()
            land.move(to: canvas.point(-0.01, horizon - 0.002))
            var x = -0.01
            while x < 0.42 {
                let rise = smoothstep(-0.01, 0.12, x) * (1 - smoothstep(0.2, 0.42, x))
                let height = 0.03 * rise * (0.7 + 0.5 * noise.fractal(x * 18, 2, octaves: 4))
                land.addLine(to: canvas.point(x, horizon + height * headland))
                x += 0.004
            }
            land.addLine(to: canvas.point(0.42, horizon - 0.002))
            land.closeSubpath()
            canvas.context.addPath(land)
            canvas.context.setFillColor(reflection.mixed(with: deep, 0.35).cgColor(0.85))
            canvas.solid { $0.fillPath() }
        }
        canvas.blur(0.0012)

        // Glitter: sparks of sunlight on wave crests, densest under the sun and
        // larger closer to the camera.
        // First the broad sheen of the sun on the water, then the sparks on it.
        canvas.context.saveGState()
        canvas.context.clip(to: canvas.rect(0, 0, 1, horizon))
        canvas.context.translateBy(x: canvas.point(sun.x, 0).x, y: canvas.point(0, horizon).y)
        canvas.context.scaleBy(x: 0.32, y: 1)
        canvas.layer(.screen) {
            canvas.glow(sunColor, at: (0, -0.12), radius: 0.55, alpha: 0.3)
        }
        canvas.context.restoreGState()
        var random = ArtRandom(seed: seed ^ 0x51)
        let spark = sunColor.mixed(with: .white, 0.5)
        for _ in 0..<3200 {
            let distance = max(0.002, pow(random.unit(), 1.5) * horizon)
            let v = horizon - distance
            let spread = 0.03 + distance * 0.4
            let u = sun.x + random.normal() * spread * 0.5
            let depth = 0.18 / (distance + 0.012)
            // Only the facets of small waves that happen to face the sun flash.
            let facet = noise.value((u - 0.5) * depth * 9 + 40, depth * 30)
            guard facet > 0.55 else { continue }
            let width = (0.0012 + distance * 0.01) * random.range(0.4...1.5)
            let height = width * random.range(0.25...0.45)
            let strength = smoothstep(0.55, 0.8, facet) * (1 - smoothstep(0, spread, abs(u - sun.x)))
            canvas.addLight(spark, ellipse: CGRect(x: u - width / 2, y: v - height / 2, width: width, height: height), alpha: strength * 0.9)
        }
    }
}
