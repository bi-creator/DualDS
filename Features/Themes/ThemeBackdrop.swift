// DualDS — procedural backdrops for the era themes (original art, drawn in code).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

/// Full-screen background for a theme. Static (drawn once per size), so it costs no battery.
struct ThemeBackdrop: View {
    let theme: AppTheme
    /// Full-screen backgrounds extend under the safe areas; previews (tiles) must stay inside their frame,
    /// or their touch area grows past what is drawn.
    var fullScreen = true

    var body: some View {
        ZStack {
            if theme == .classic {
                Color(.systemBackground)
            } else {
                LinearGradient(colors: theme.backgroundColors, startPoint: .top, endPoint: .bottom)
                Canvas { ctx, size in BackdropArt.draw(theme, in: &ctx, size: size) }
            }
        }
        .ignoresSafeArea(edges: fullScreen ? .all : [])
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small deterministic PRNG (SplitMix64) so a theme's pattern never changes between launches.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ r: ClosedRange<Double>) -> Double { r.lowerBound + unit() * (r.upperBound - r.lowerBound) }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
}

enum BackdropArt {
    static func draw(_ theme: AppTheme, in ctx: inout GraphicsContext, size: CGSize) {
        var rng = SeededRandom(seed: theme.seed)
        switch theme {
        case .classic: break
        case .neonMaze: neonMaze(&ctx, size, &rng)
        case .vectorVoid: vectorVoid(&ctx, size, &rng)
        case .pixelKingdom: pixelKingdom(&ctx, size, &rng)
        case .dungeonMap: dungeonMap(&ctx, size, &rng)
        case .blockRain: blockRain(&ctx, size, &rng)
        case .pocketGreen: pocketGreen(&ctx, size, &rng)
        case .speedZone: speedZone(&ctx, size, &rng)
        case .streetBrawl: streetBrawl(&ctx, size, &rng)
        case .polygonRally: polygonRally(&ctx, size, &rng)
        case .fogTown: fogTown(&ctx, size, &rng)
        }
    }

    // 1980: glowing maze walls on a grid, with rows of small dots.
    private static func neonMaze(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let cell: CGFloat = 40
        var walls = Path(), dots = Path()
        for gx in stride(from: 0, through: size.width, by: cell) {
            for gy in stride(from: 0, through: size.height, by: cell) {
                let r = rng.unit()
                if r < 0.28 { walls.move(to: CGPoint(x: gx, y: gy)); walls.addLine(to: CGPoint(x: gx + cell, y: gy)) }
                else if r < 0.52 { walls.move(to: CGPoint(x: gx, y: gy)); walls.addLine(to: CGPoint(x: gx, y: gy + cell)) }
                else if r < 0.80 {
                    dots.addEllipse(in: CGRect(x: gx + cell / 2 - 2, y: gy + cell / 2 - 2, width: 4, height: 4))
                }
            }
        }
        ctx.stroke(walls, with: .color(Color(hex: 0x2D5BFF, opacity: 0.22)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        ctx.stroke(walls, with: .color(Color(hex: 0x5C86FF, opacity: 0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        ctx.fill(dots, with: .color(Color(hex: 0xFFC8F0, opacity: 0.55)))
    }

    // 1981: starfield and drifting wireframe rocks.
    private static func vectorVoid(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        var stars = Path()
        for _ in 0..<160 {
            let s = rng.range(0.8...2.0)
            stars.addEllipse(in: CGRect(x: rng.unit() * size.width, y: rng.unit() * size.height, width: s, height: s))
        }
        ctx.fill(stars, with: .color(.white.opacity(0.6)))
        for _ in 0..<16 {
            let c = CGPoint(x: rng.unit() * size.width, y: rng.unit() * size.height)
            let radius = rng.range(12...46)
            let n = Int(rng.range(6...10))
            var poly = Path()
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi
                let r = radius * rng.range(0.7...1.1)
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { poly.move(to: p) } else { poly.addLine(to: p) }
            }
            poly.closeSubpath()
            ctx.stroke(poly, with: .color(Color(hex: 0x7DFFB2, opacity: 0.55)), lineWidth: 1.4)
        }
        // A faint perspective grid near the bottom.
        var grid = Path()
        let horizon = size.height * 0.78
        for i in -12...12 {
            grid.move(to: CGPoint(x: size.width / 2, y: horizon))
            grid.addLine(to: CGPoint(x: size.width / 2 + CGFloat(i) * size.width / 6, y: size.height))
        }
        var y = horizon, step: CGFloat = 6
        while y < size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += step; step *= 1.35 }
        ctx.stroke(grid, with: .color(Color(hex: 0x7DFFB2, opacity: 0.18)), lineWidth: 1)
    }

    // 1985: blocky clouds, stepped hills and a brick floor.
    private static func pixelKingdom(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let p: CGFloat = 8
        func snap(_ v: CGFloat) -> CGFloat { (v / p).rounded() * p }
        for _ in 0..<6 {
            let x = snap(rng.unit() * size.width), y = snap(rng.range(0.05...0.45) * size.height)
            let w = snap(rng.range(56...120))
            var cloud = Path()
            cloud.addRect(CGRect(x: x, y: y + p * 2, width: w, height: p * 3))
            cloud.addRect(CGRect(x: x + p * 2, y: y, width: w - p * 4, height: p * 2))
            cloud.addRect(CGRect(x: x + p, y: y + p, width: w - p * 2, height: p))
            ctx.fill(cloud, with: .color(.white.opacity(0.85)))
        }
        let ground = size.height - p * 6
        for (index, colour) in [Color(hex: 0x6CC36A), Color(hex: 0x3F9E4A)].enumerated() {
            var hills = Path()
            var h = size.height * (index == 0 ? 0.30 : 0.18)
            var x: CGFloat = 0
            hills.move(to: CGPoint(x: 0, y: ground))
            while x < size.width + p * 4 {
                h += CGFloat(rng.range(-1...1)) * p * 2
                h = min(max(h, size.height * 0.08), size.height * 0.40)
                hills.addLine(to: CGPoint(x: x, y: snap(ground - h)))
                x += p * 4
                hills.addLine(to: CGPoint(x: x, y: snap(ground - h)))
            }
            hills.addLine(to: CGPoint(x: x, y: ground))
            hills.closeSubpath()
            ctx.fill(hills, with: .color(colour))
        }
        ctx.fill(Path(CGRect(x: 0, y: ground, width: size.width, height: size.height - ground)), with: .color(Color(hex: 0xB5582B)))
        var mortar = Path()
        var row = 0
        for y in stride(from: ground, to: size.height, by: p * 2) {
            mortar.move(to: CGPoint(x: 0, y: y)); mortar.addLine(to: CGPoint(x: size.width, y: y))
            for x in stride(from: (row % 2 == 0 ? 0 : p * 2), to: size.width, by: p * 4) {
                mortar.move(to: CGPoint(x: x, y: y)); mortar.addLine(to: CGPoint(x: x, y: y + p * 2))
            }
            row += 1
        }
        ctx.stroke(mortar, with: .color(Color(hex: 0x6E2E12)), lineWidth: 2)
    }

    // 1986: worn stone floor lit by a few torches.
    private static func dungeonMap(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let tile: CGFloat = 32
        for x in stride(from: 0, to: size.width, by: tile) {
            for y in stride(from: 0, to: size.height, by: tile) {
                let shade = rng.range(0.0...0.10)
                ctx.fill(Path(roundedRect: CGRect(x: x + 1.5, y: y + 1.5, width: tile - 3, height: tile - 3), cornerRadius: 3),
                         with: .color(Color(hex: 0x3A372D).opacity(0.55 + shade * 3)))
            }
        }
        for _ in 0..<5 {
            let c = CGPoint(x: rng.unit() * size.width, y: rng.unit() * size.height)
            let r = rng.range(90...170)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xFF9F3C, opacity: 0.32), .clear]),
                                           center: c, startRadius: 0, endRadius: r))
        }
    }

    // 1989: a faint well grid with loose clusters of coloured cells.
    private static func blockRain(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let cell: CGFloat = 26
        var grid = Path()
        for x in stride(from: 0, through: size.width, by: cell) { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
        for y in stride(from: 0, through: size.height, by: cell) { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
        ctx.stroke(grid, with: .color(.white.opacity(0.05)), lineWidth: 1)
        let colours = [Color(hex: 0xE2534B), Color(hex: 0xF7B32B), Color(hex: 0x2F8FC4), Color(hex: 0x3FA873), Color(hex: 0x9B6BD6)]
        let cols = Int(size.width / cell), rows = Int(size.height / cell)
        guard cols > 2, rows > 2 else { return }
        for _ in 0..<22 {
            var cx = Int(rng.unit() * Double(cols)), cy = Int(rng.unit() * Double(rows))
            let colour = colours[Int(rng.unit() * Double(colours.count)) % colours.count]
            for _ in 0..<Int(rng.range(2...5)) {
                let r = CGRect(x: CGFloat(cx) * cell + 2, y: CGFloat(cy) * cell + 2, width: cell - 4, height: cell - 4)
                ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(colour.opacity(0.42)))
                ctx.stroke(Path(roundedRect: r.insetBy(dx: 3, dy: 3), cornerRadius: 2), with: .color(.white.opacity(0.18)), lineWidth: 1.5)
                if rng.chance(0.5) { cx += rng.chance(0.5) ? 1 : -1 } else { cy += 1 }
            }
        }
    }

    // 1989: four-shade green with a soft dot-matrix texture.
    private static func pocketGreen(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        var dots = Path()
        let step: CGFloat = 6
        for y in stride(from: 0, to: size.height, by: step) {
            for x in stride(from: 0, to: size.width, by: step) { dots.addRect(CGRect(x: x, y: y, width: 4.5, height: 4.5)) }
        }
        ctx.fill(dots, with: .color(Color(hex: 0x306230, opacity: 0.08)))
        for i in 0..<3 {
            let y = size.height * (0.55 + Double(i) * 0.15)
            var band = Path()
            band.addRect(CGRect(x: 0, y: y, width: size.width, height: size.height * 0.15))
            ctx.fill(band, with: .color(Color(hex: 0x306230, opacity: 0.10 + Double(i) * 0.06)))
        }
        _ = rng.next()
    }

    // 1991: speed streaks and chevrons racing across a dusk sky.
    private static func speedZone(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let colours = [Color.white, Color(hex: 0xFFD23F), Color(hex: 0x5AD8FF)]
        for _ in 0..<42 {
            let y = rng.unit() * size.height, x = rng.range(-0.2...1.0) * size.width
            let length = rng.range(60...260), width = rng.range(2...6)
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x + length, y: y - length * 0.18))
            ctx.stroke(streak, with: .color(colours[Int(rng.unit() * 3) % 3].opacity(rng.range(0.15...0.45))),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        for i in 0..<3 {
            let base = CGPoint(x: size.width * 0.62 + CGFloat(i) * 34, y: size.height * 0.86)
            var chevron = Path()
            chevron.move(to: CGPoint(x: base.x, y: base.y - 18))
            chevron.addLine(to: CGPoint(x: base.x + 18, y: base.y))
            chevron.addLine(to: CGPoint(x: base.x, y: base.y + 18))
            ctx.stroke(chevron, with: .color(Color(hex: 0xFFD23F, opacity: 0.35 + Double(i) * 0.2)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
    }

    // 1991: halftone sunset over a city skyline with lit windows.
    private static func streetBrawl(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let step: CGFloat = 14
        var halftone = Path()
        for y in stride(from: 0, to: size.height * 0.6, by: step) {
            let r = max(0.4, 4.5 * (1 - y / (size.height * 0.6)))
            for x in stride(from: (Int(y / step) % 2 == 0 ? 0 : step / 2), to: size.width, by: step) {
                halftone.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        ctx.fill(halftone, with: .color(Color(hex: 0xFF7A3C, opacity: 0.18)))
        var x: CGFloat = 0
        while x < size.width {
            let w = rng.range(36...80), h = rng.range(0.16...0.40) * size.height
            let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
            ctx.fill(Path(rect), with: .color(Color(hex: 0x170707)))
            var windows = Path()
            for wy in stride(from: rect.minY + 10, to: rect.maxY - 8, by: 14) {
                for wx in stride(from: rect.minX + 6, to: rect.maxX - 8, by: 12) where rng.chance(0.3) {
                    windows.addRect(CGRect(x: wx, y: wy, width: 5, height: 7))
                }
            }
            ctx.fill(windows, with: .color(Color(hex: 0xFFB347, opacity: 0.55)))
            x += w + rng.range(2...8)
        }
    }

    // 1997: low-poly mountains, a setting sun and a road to the horizon.
    private static func polygonRally(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let horizon = size.height * 0.58
        let sun = CGRect(x: size.width * 0.62, y: horizon - 120, width: 150, height: 150)
        ctx.fill(Path(ellipseIn: sun), with: .color(Color(hex: 0xFFD27A, opacity: 0.85)))
        let tones = [Color(hex: 0xC98B5E), Color(hex: 0xB47148), Color(hex: 0x8E5536), Color(hex: 0xA5643F)]
        var x: CGFloat = -40
        while x < size.width {
            let w = rng.range(70...160), h = rng.range(50...150)
            var tri = Path()
            tri.move(to: CGPoint(x: x, y: horizon))
            tri.addLine(to: CGPoint(x: x + w * rng.range(0.35...0.65), y: horizon - h))
            tri.addLine(to: CGPoint(x: x + w, y: horizon))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(tones[Int(rng.unit() * 4) % 4]))
            x += w * 0.6
        }
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)), with: .color(Color(hex: 0xD9A46C)))
        var road = Path()
        road.move(to: CGPoint(x: size.width * 0.47, y: horizon))
        road.addLine(to: CGPoint(x: size.width * 0.53, y: horizon))
        road.addLine(to: CGPoint(x: size.width * 0.95, y: size.height))
        road.addLine(to: CGPoint(x: size.width * 0.05, y: size.height))
        road.closeSubpath()
        ctx.fill(road, with: .color(Color(hex: 0x4A4A4E)))
        var dash = Path()
        var t: CGFloat = 0.05
        while t < 1 {
            let y0 = horizon + (size.height - horizon) * t, y1 = horizon + (size.height - horizon) * min(1, t * 1.25)
            dash.move(to: CGPoint(x: size.width / 2, y: y0)); dash.addLine(to: CGPoint(x: size.width / 2, y: y1))
            t *= 1.6
        }
        ctx.stroke(dash, with: .color(.white.opacity(0.9)), lineWidth: 3)
    }

    // 1999: a dim town in drifting fog with a few warm windows and film grain.
    private static func fogTown(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        var x: CGFloat = 0
        var windows = Path()
        while x < size.width {
            let w = rng.range(40...90), h = rng.range(0.20...0.45) * size.height
            let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
            ctx.fill(Path(rect), with: .color(Color(hex: 0x2A302D)))
            if rng.chance(0.5) { windows.addRect(CGRect(x: rect.minX + w * 0.3, y: rect.minY + 24, width: 6, height: 9)) }
            x += w + rng.range(4...14)
        }
        ctx.fill(windows, with: .color(Color(hex: 0xE8C37A, opacity: 0.55)))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 24))
            for i in 0..<6 {
                let y = size.height * (0.35 + Double(i) * 0.11)
                layer.fill(Path(roundedRect: CGRect(x: -60, y: y, width: size.width + 120, height: 60), cornerRadius: 30),
                           with: .color(.white.opacity(0.05 + Double(i % 3) * 0.02)))
            }
        }
        var grain = Path()
        for _ in 0..<500 { grain.addRect(CGRect(x: rng.unit() * size.width, y: rng.unit() * size.height, width: 1, height: 1)) }
        ctx.fill(grain, with: .color(.white.opacity(0.08)))
    }
}
