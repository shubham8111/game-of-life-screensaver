import Foundation

/// The scene catalogue. Each scene lays out patterns on a `Stage` in
/// screen-relative positions, so it fits any display. See README.md for how
/// to add one.
private typealias P = Patterns

extension Scene {
    static let all: [Scene] = [
        crossfire, armada, lanternGarden, supernova, contrails, clockwork,
        bigBang, nightSky, monsoon, twoKingdoms, life,
    ]

    /// Four Gosper guns in the corners, all aimed at the centre. The streams
    /// meet in a symmetric fire that grows until it swallows the guns.
    static let crossfire = Scene(
        name: "Crossfire",
        palette: [0, 0x22D3EE, 0xF472B6, 0xFBBF24, 0xA3E635, 0xF8FAFC],
        mixColor: 5, generations: 5000, stagnationAfter: 600
    ) { s in
        s.symmetry = .mirror4
        s.imageColors = [1, 2, 3, 4]
        // The stream runs along x - y = gunX - gunY + 14. Aimed exactly through the
        // centre the four streams annihilate quietly; these offsets (found by
        // sweeping them) make them graze each other and catch fire.
        let gy = max(2, s.cy - max(26, s.minDim * 2 / 5)) + s.random(0...8)
        let off = [-18, -17, -15, 15, 16][s.random(0...4)]
        let gx = gy + s.cx - s.cy - 14 + off
        s.gun(.gosper, gx, gy, eater: nil, gunColor: 1, eaterColor: 1)
    }

    /// A V of spaceships with a gold flagship flies into an asteroid belt of
    /// still lifes; a second squadron comes the other way, and slow
    /// copperheads arrive long after.
    static let armada = Scene(
        name: "Armada",
        palette: [0, 0x60A5FA, 0x93C5FD, 0x818CF8, 0xFDE047, 0xA8A29E, 0xFB923C, 0xF59E0B, 0xF9A8D4],
        mixColor: 6,
        mixes: [(1, 5, 6), (2, 5, 6), (3, 5, 6), (4, 5, 6), (7, 5, 6), (8, 5, 6), (6, 5, 6)],
        generations: 4500, stagnationAfter: 2000
    ) { s in
        let ships = [P.lwss, P.mwss, P.hwss]
        let ranks = max(2, min(6, (s.cy - 12) / 9))
        s.ship(P.hwss, .e, -8, s.cy, 4)
        for k in 1...ranks {
            let t = k % 3
            s.ship(ships[t], .e, -8 - 6 * k, s.cy - 9 * k, UInt8(t + 1))
            s.ship(ships[t], .e, -8 - 6 * k, s.cy + 9 * k, UInt8(t + 1))
        }
        // The belt.
        let rocks = [P.block, P.beehive, P.loaf, P.boat, P.tub, P.pond, P.ship]
        let o: [Orientation] = [.identity, .rot90, .rot180, .rot270, .flipX]
        var y = 6
        while y < s.H - 6 {
            var x = s.x(0.42)
            while x < s.x(0.62) {
                if s.chance(0.6) {
                    let r = rocks[s.random(0...rocks.count - 1)]
                    s.center(r, x + s.random(-2...2), y + s.random(-2...2), o[s.random(0...4)], 5)
                }
                x += 11
            }
            y += 11
        }
        // The counter-attack: a smaller V coming from the east.
        s.at(260) { s in
            s.ship(P.mwss, .w, s.W + 8, s.cy, 8)
            for k in 1...max(1, ranks - 2) {
                s.ship(P.lwss, .w, s.W + 8 + 6 * k, s.cy - 9 * k, 8)
                s.ship(P.lwss, .w, s.W + 8 + 6 * k, s.cy + 9 * k, 8)
            }
        }
        s.at(160) { s in
            for dy in [-s.H / 4, 0, s.H / 4] { s.ship(P.copperhead, .e, -24, s.cy + dy + 4, 7) }
        }
    }

    /// A staggered grid of oscillators glowing like paper lanterns, in
    /// concentric diamonds of species. After a calm minute and a half, stray
    /// gliders drift in and set the garden alight.
    static let lanternGarden = Scene(
        name: "Lantern Garden",
        palette: [0, 0xFBBF24, 0xFB923C, 0xFB7185, 0xF87171, 0xFDE68A, 0xFDBA74, 0xEF4444, 0xFFFFFF, 0xFCA5A5],
        mixColor: 9, generations: 5000, stagnationAfter: 1500
    ) { s in
        let species: [(Pattern, UInt8)] = [
            (P.pulsar, 1), (P.octagon2, 5), (P.trafficLight, 3), (P.pentadecathlon, 2),
            (P.figureEight, 4), (P.tumbler, 6), (P.queenBeeShuttle, 7),
        ]
        let px = 30, py = 26
        let nx = max(1, (s.W - 8) / px), ny = max(1, (s.H - 4) / py)
        let x0 = (s.W - (nx - 1) * px) / 2, y0 = (s.H - (ny - 1) * py) / 2
        for j in 0..<ny {
            let shift = j % 2 == 1 ? px / 2 : 0
            for i in 0..<(j % 2 == 1 ? nx - 1 : nx) {
                let ring = abs(2 * i + (j % 2) - (nx - 1)) / 2 + abs(j - (ny - 1) / 2)
                let (p, c) = species[ring % species.count]
                let o: Orientation = (i + j) % 2 == 0 ? .identity : .rot90
                s.center(p, x0 + shift + i * px, y0 + j * py, p.width > 12 ? .identity : o, c)
            }
        }
        s.at(1350) { s in s.place(P.glider, -20, -20, .identity, 8) }
        s.at(1650) { s in s.place(P.glider.heading(.nw), s.W + 16, s.H + 16, .identity, 8) }
        s.at(2100) { s in s.place(P.glider.heading(.sw), s.W + 16, -20, .identity, 8) }
    }

    /// Rings of pentadecathlons, pulsars and octagons in perfect 8-fold
    /// symmetry around a methuselah core that ignites and eats them.
    static let supernova = Scene(
        name: "Supernova",
        palette: [0, 0x8B5CF6, 0xA855F7, 0xD946EF, 0xF43F5E, 0xF97316, 0xFACC15, 0xFFFFFF],
        mixColor: 7, generations: 5000, stagnationAfter: 800
    ) { s in
        supernovaLayout(s, core: P.bHeptomino.oriented(.rot270), dx: 5, dy: 2)
    }

    /// The core (offset from the centre, replicated 8-fold) is the seed that, of
    /// hundreds swept, tears through the most rings.
    static func supernovaLayout(_ s: Stage, core: Pattern, dx: Int, dy: Int) {
        s.symmetry = .mirror8
        s.place(core, s.cx + dx, s.cy + dy, .identity, 6)
        func at(_ r: Double, _ deg: Double) -> (Int, Int) {
            let a = deg * .pi / 180
            return (s.cx + Int((r * cos(a)).rounded()), s.cy + Int((r * sin(a)).rounded()))
        }
        // Radii in cells (not screen fractions) so the explosion meets the rings
        // exactly as tuned, on any display.
        let h = 196.0
        let (ax, ay) = at(0.14 * h, 22.5); s.center(P.pentadecathlon, ax, ay, .identity, 5)
        let (bx, by) = at(0.25 * h, 22.5); s.center(P.pulsar, bx, by, .identity, 4)
        let (cx1, cy1) = at(0.37 * h, 11.25); s.center(P.octagon2, cx1, cy1, .identity, 3)
        let (cx2, cy2) = at(0.37 * h, 33.75); s.center(P.figureEight, cx2, cy2, .identity, 2)
        // Wide screens: columns of pulsars in the side panels.
        s.symmetry = .mirror4
        let side = (s.W - s.H) / 2
        if side > 30 {
            var y = s.cy - 12
            while y > 8 { s.center(P.pulsar, side / 2 - 2, y, .identity, 1); y -= 24 }
        }
    }

    /// A formation of block-laying switch engines climbs from below the horizon
    /// like jets at sunset, each drawing a dotted contrail of blocks; much later
    /// one flies the other way into their trails and flares up.
    static let contrails = Scene(
        name: "Contrails",
        palette: [0, 0xFB923C, 0xF472B6, 0xC084FC, 0xFCD34D, 0xFDA4AF, 0xFFF1E6],
        mixColor: 6, generations: 5000, stagnationAfter: 3500, flipY: false
    ) { s in
        // A staggered formation heading north-west, launched just below the
        // screen. (Engines meeting head-on simply annihilate, so they fly parallel.)
        let n = max(3, min(8, s.W / 50))
        let spacing = (s.W + s.H / 2) / n
        for i in 0..<n {
            let x = s.W / 5 + i * spacing + s.random(-6...6)
            s.at(i * 140 + s.random(0...60)) { s in
                s.place(P.blockLayingEngine, x, s.H + 2, .identity, UInt8(i % 5 + 1))
            }
        }
        // Much later, one climbing the other way flies into their trails and flares.
        s.at(1500) { s in s.place(P.blockLayingEngine, s.W / 10, s.H + 2, .flipX, 6) }
        s.preroll = 900
    }

    /// A circuit board of glider guns whose streams run into eaters: a
    /// perfect machine, until one eater goes missing.
    static let clockwork = Scene(
        name: "Clockwork",
        palette: [0, 0xD97706, 0x22D3EE, 0xEF4444, 0xFDE68A, 0xFFFFFF],
        mixColor: 5, mixes: [(1, 2, 4), (2, 3, 4)], generations: 5000, stagnationAfter: 1900
    ) { s in
        s.symmetry = .mirror4
        var eaters: [Rect] = [], guns: [Rect] = []
        let stack = max(1, min(4, (s.cy - 10) / 30))
        for i in 0..<stack {
            let gy = 4 + 30 * i   // any closer and a stream clips the gun below
            let k = max(0, min(s.cy - 12 - gy - 15 - 3, s.cx - 8 - 4 - 29 - 3))
            let r = s.gun(.gosper, 4, gy, eater: k, gunColor: 1, eaterColor: 3)
            guns.append(r.gun); eaters.append(r.eater!)
        }
        // A Simkin gun placed where the first stream, once freed, will hit its mirror image.
        let sx = max(54, s.W - s.H - 20)
        if sx + 33 < s.cx - 10 {
            let k = max(0, min(s.cx - 8 - sx - 28 - 4, s.cy - 8 - 4 - 32 - 4))
            let r = s.gun(.simkin, sx, 4, eater: k, gunColor: 1, eaterColor: 3)
            guns.append(r.gun); eaters.append(r.eater!)
        }
        // Lanes glow cyan, guns copper, eaters red (dyes are not mirrored, so add all four images).
        func images(_ r: Rect) -> [Rect] {
            [r, Rect(x0: s.W - 1 - r.x1, y0: r.y0, x1: s.W - 1 - r.x0, y1: r.y1),
             Rect(x0: r.x0, y0: s.H - 1 - r.y1, x1: r.x1, y1: s.H - 1 - r.y0),
             Rect(x0: s.W - 1 - r.x1, y0: s.H - 1 - r.y1, x1: s.W - 1 - r.x0, y1: s.H - 1 - r.y0)]
        }
        // Gliders are born copper from their gun; turn them cyan once they leave it.
        s.dye(Rect(x0: -s.M, y0: -s.M, x1: s.W + s.M - 1, y1: s.H + s.M - 1), from: 1, 2)
        for g in guns { for r in images(g) { s.dye(r, 1) } }
        for e in eaters { for r in images(Rect(x0: e.x0 - 1, y0: e.y0 - 1, x1: e.x1 + 1, y1: e.y1 + 1)) { s.dye(r, 3) } }
        let victim = eaters[0]
        s.at(1800) { s in s.clear(victim) }
    }

    /// Salvos from all eight compass points, timed to meet at the centre:
    /// spaceships from the sides, gliders from the corners, wave after wave.
    static let bigBang = Scene(
        name: "Big Bang",
        palette: [0, 0xEF4444, 0xF97316, 0xEAB308, 0x22C55E, 0x14B8A6, 0x3B82F6, 0x8B5CF6, 0xEC4899, 0xFFFFFF],
        mixColor: 9, generations: 4000, stagnationAfter: 1200, hueJitter: 0
    ) { s in
        bigBangLayout(s, plan: bigBangPlans[s.random(0...bigBangPlans.count - 1)])
    }

    /// Salvo plans (seeds for `bigBangLayout`) that end in a big, long-lived
    /// firework rather than a quiet annihilation; found by sweeping seeds.
    static let bigBangPlans: [UInt64] = [532, 2149, 1856, 1360, 55, 34, 631]

    static func bigBangLayout(_ s: Stage, plan: UInt64) {
        var r = SplitMix64(seed: plan)
        func rnd(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &r) }
        // Launch distances with fixed parity, so arrival phases (and hence the
        // collisions) are the same on every screen size.
        let dh = 24 + (s.cx + 24) % 2, dv = 24 + (s.cy + 24) % 2, g = s.cy + 24
        let arrive = 4 * g + 8
        let ships = [P.lwss, P.mwss, P.hwss]
        let waves = rnd(4...7), spacing = rnd(40...64)
        for w in 0..<waves {
            let t = arrive + w * spacing
            let ship = ships[rnd(0...2)], ship2 = ships[rnd(0...2)]
            // Offsets of 6+ keep a ship clear of its own mirror image.
            let offH = rnd(6...14), offV = rnd(6...14), gdx = rnd(-3...3)
            let jh = rnd(-4...4), jv = rnd(-4...4), jg = rnd(-4...4)
            s.at(t + jh - 2 * (s.cx + dh)) { s in
                s.symmetry = .mirror4; s.imageColors = [7, 3, 7, 3]
                s.ship(ship, .e, -dh, s.cy - offH, 1)
            }
            s.at(t + jv - 2 * (s.cy + dv)) { s in
                s.symmetry = .mirror4; s.imageColors = [1, 1, 5, 5]
                s.ship(ship2, .s, s.cx - offV, -dv, 1)
            }
            s.at(t + 4 * jg - 4 * g) { s in
                s.symmetry = .mirror4; s.imageColors = [8, 2, 6, 4]
                s.center(P.glider, s.cx - g + gdx, s.cy - g, .identity, 1)
            }
        }
        s.preroll = 100
    }

    /// Constellations of twinkling blinkers, a pulsar moon, shooting stars and
    /// a nebula slowly blooming from an acorn in the corner.
    static let nightSky = Scene(
        name: "Night Sky",
        palette: [0, 0x8EA2C8, 0xE0E7FF, 0xFEF3C7, 0xFFFFFF, 0xA78BFA, 0x2DD4BF, 0xF0ABFC, 0xFCA5A5, 0x93C5FD],
        mixColor: 7,
        generations: 6000, stagnationAfter: 5000, flipX: false, flipY: false, hueJitter: 0
    ) { s in
        var stars: [(Int, Int)] = []
        func star(_ x: Int, _ y: Int, _ p: Pattern, _ c: UInt8) {
            s.center(p, x, y, .identity, c)
            stars.append((x, y))
        }
        func constellation(_ pts: [(Double, Double, UInt8)], _ fx: Double, _ fy: Double, _ fw: Double, _ fh: Double) {
            for (u, v, c) in pts {
                star(s.x(fx + u * fw), s.y(fy + v * fh), P.beacon, c)
            }
        }
        // Big Dipper (upper left).
        constellation([(0.00, 0.30, 2), (0.17, 0.12, 2), (0.32, 0.08, 2), (0.47, 0.18, 2),
                       (0.50, 0.42, 2), (0.80, 0.50, 2), (0.86, 0.20, 2)], 0.06, 0.08, 0.34, 0.36)
        // Orion (right): red Betelgeuse, blue Rigel.
        constellation([(0.15, 0.10, 8), (0.75, 0.18, 2), (0.45, 0.00, 2), (0.38, 0.52, 2),
                       (0.48, 0.48, 2), (0.58, 0.44, 2), (0.25, 0.92, 2), (0.82, 0.85, 9)], 0.55, 0.30, 0.22, 0.58)
        // The moon.
        s.center(P.pulsar, s.x(0.88), s.y(0.16), .identity, 3)
        stars.append((s.x(0.88), s.y(0.16)))
        // Faint background stars away from everything else.
        for _ in 0..<(s.W * s.H / 1500) {
            let x = s.random(4...(s.W - 5)), y = s.random(4...(s.H - 5))
            guard stars.allSatisfy({ abs($0.0 - x) > 9 || abs($0.1 - y) > 9 }) else { continue }
            guard x > s.x(0.3) || y < s.y(0.55) else { continue }   // keep the nebula's corner dark
            star(x, y, s.chance(0.7) ? P.blinker : P.block, 1)
        }
        // The nebula: an acorn, half purple and half teal.
        let a = P.acorn
        let nx = s.x(0.22), ny = s.y(0.76)
        for (i, c) in a.cells.enumerated() { s.set(nx + c.0, ny + c.1, i % 2 == 0 ? 5 : 6) }
        // Shooting stars.
        for (t, fy, west) in [(240, 0.05, true), (900, 0.62, false), (1700, 0.22, true), (2600, 0.45, false), (3500, 0.12, true)] {
            s.at(t) { s in
                s.ship(P.lwss, west ? .w : .e, west ? s.W + 10 : -10, s.y(fy), 4)
            }
        }
    }

    /// Wind-driven glider rain from guns hidden above the screen falls on a
    /// skyline of still lifes. Eater lightning rods take some of it; the rest
    /// sets the city on fire.
    static let monsoon = Scene(
        name: "Monsoon",
        palette: [0, 0x7DD3FC, 0xF59E0B, 0xFDE68A, 0xF87171, 0xFB923C, 0xD97706],
        mixColor: 5, mixes: [(1, 2, 5), (1, 6, 5), (1, 3, 5)],
        generations: 5000, stagnationAfter: 1500, flipY: false
    ) { s in
        // The skyline: towers of blocks on a 3-cell lattice (a stable arrangement).
        var roofs: [(x0: Int, x1: Int, top: Int)] = []
        var x = 3
        while x < s.W - 10 {
            let wb = s.random(3...7), hb = s.random(3...max(4, s.H / 18))
            let top = s.H - 3 - 3 * hb
            // Solid (holes would leave unstable inside corners); some windows lit.
            for by in 0..<hb { for bx in 0..<wb {
                let lit = by > 0 && bx > 0 && bx < wb - 1 && s.chance(0.22)
                s.place(P.block, x + 3 * bx, top + 3 * by + 1, .identity, lit ? 3 : 2)
            } }
            roofs.append((x, x + 3 * wb - 2, top + 1))
            x += 3 * wb + s.random(3...8)
        }
        // Rain: guns in the hidden top margin, every third one a sparse Simkin.
        var gx = -50, n = 0
        var rodded = Set<Int>()
        while gx < s.W - 30 {
            let gun: Gun = n % 3 == 2 ? .simkin : .gosper
            let gy = gun == .gosper ? -34 : -44
            // A lightning rod where this stream first meets a roof (sometimes).
            var k: Int?
            if s.chance(0.6) {
                for kk in stride(from: 0, to: 600, by: 1) {
                    let (ex, ey) = gun.eaterOffset(kk)
                    let ax = gx + ex, ay = gy + ey
                    // Two clear rows between the rod and the roof keep both stable.
                    if let i = roofs.firstIndex(where: { ax >= $0.x0 && ax + 3 <= $0.x1 && ay + 3 == $0.top - 3 }),
                       !rodded.contains(i) {
                        k = kk; rodded.insert(i); break
                    }
                    if ay > s.H { break }
                }
            }
            s.gun(gun, gx, gy, eater: k, gunColor: 1, eaterColor: 4)
            gx += gun == .gosper ? 44 : 41
            n += 1
        }
        // Domes on the unprotected roofs.
        for (i, r) in roofs.enumerated() where !rodded.contains(i) && s.chance(0.5) {
            s.center(P.beehive, (r.x0 + r.x1) / 2, r.top - 4, .rot90, 6)
        }
        s.preroll = 4 * (s.H * 3 / 5)
    }

    /// Two kingdoms of block-lattice fortresses, red and blue, each with a
    /// methuselah king in its central plaza. Each king's fire spreads through
    /// its own fortresses; shrapnel crosses the border and where the two fires
    /// meet, newborn cells turn violet.
    static let twoKingdoms = Scene(
        name: "Two Kingdoms",
        palette: [0, 0xEF4444, 0x3B82F6, 0xA855F7, 0x64748B, 0xFCA5A5, 0x93C5FD],
        mixColor: 3,
        mixes: [(1, 2, 3), (5, 6, 3), (1, 6, 3), (2, 5, 3), (1, 5, 1), (2, 6, 2)],
        generations: 6000, stagnationAfter: 2500
    ) { s in
        let kings = [(s.x(0.25), s.cy), (s.x(0.75), s.cy)]
        // Fortresses: solid rectangles of blocks on a 3-cell lattice (stable, and good fuel).
        var y = 6
        while y < s.H - 12 {
            var x = 6
            while x < s.W - 12 {
                let wb = s.random(2...4), hb = s.random(2...4)
                let fx = x + s.random(0...3), fy = y + s.random(0...3)
                let mx = fx + 3 * wb / 2, my = fy + 3 * hb / 2
                let inPlaza = kings.contains { abs($0.0 - mx) < 13 && abs($0.1 - my) < 13 }
                let onBorder = abs(mx - s.cx) < 10
                if !inPlaza && !onBorder && fx + 3 * wb < s.W - 4 && fy + 3 * hb < s.H - 4 && s.chance(0.85) {
                    let c: UInt8 = mx < s.cx ? 5 : 6
                    for by in 0..<hb { for bx in 0..<wb { s.place(P.block, fx + 3 * bx, fy + 3 * by, .identity, c) } }
                }
                x += 17
            }
            y += 17
        }
        s.center(P.rPentomino, kings[0].0, kings[0].1, .identity, 1)
        s.center(P.acorn, kings[1].0, kings[1].1, .identity, 2)
    }

    /// "LIFE" in letters of blocks between rows of pentadecathlons. One by one
    /// the letters are set alight and burn away.
    static let life = Scene(
        name: "LIFE",
        palette: [0, 0x60A5FA, 0x818CF8, 0xC084FC, 0xF472B6, 0xFFFFFF, 0xE0E7FF],
        mixColor: 5, generations: 3500, stagnationAfter: 800, flipX: false, flipY: false, hueJitter: 25
    ) { s in
        lifeLayout(s, igniter: lifeIgniter.pattern, dx: lifeIgniter.dx, dy: lifeIgniter.dy)
    }

    /// What sets each letter alight, placed relative to its bottom-left corner;
    /// found by sweeping (a lone glider only nibbles the lattice).
    static let lifeIgniter: (pattern: Pattern, dx: Int, dy: Int) = (P.piHeptomino, -1, 3)

    static func lifeLayout(_ s: Stage, igniter: Pattern, dx: Int, dy: Int) {
        let font: [[String]] = [
            ["X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"],
            ["XXX", ".X.", ".X.", ".X.", ".X.", ".X.", "XXX"],
            ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "X...."],
            ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"],
        ]
        // Each font pixel is n×n blocks on a 4-cell lattice. (A 3-cell lattice is
        // only stable in solid rectangles: inside corners sprout births.)
        // Two-pixel gaps: wide enough that fire cannot jump from one letter to the next.
        let widthPx = font.map { $0[0].count }.reduce(0, +) + 2 * (font.count - 1)
        let n = widthPx * 8 + 16 <= s.W ? 2 : 1, px = 4 * n
        let x0 = s.cx - widthPx * px / 2, y0 = s.cy - 7 * px / 2
        var lx = x0
        var letters: [Rect] = []
        for (li, glyph) in font.enumerated() {
            for (row, line) in glyph.enumerated() {
                for (col, ch) in line.enumerated() where ch == "X" {
                    for by in 0..<n { for bx in 0..<n {
                        s.place(P.block, lx + col * px + bx * 4, y0 + row * px + by * 4, .identity, UInt8(li + 1))
                    } }
                }
            }
            let w = glyph[0].count * px
            letters.append(Rect(x0: lx, y0: y0, x1: lx + w - 2, y1: y0 + 7 * px - 2))
            lx += w + 2 * px
        }
        // Pentadecathlon sparkles above and below.
        var sx = x0 + 4
        while sx < x0 + widthPx * px - 6 {
            // Over its cycle a pentadecathlon spans 16×9 cells: keep them well apart.
            s.center(P.pentadecathlon, sx, y0 - 16, .identity, 6)
            s.center(P.pentadecathlon, sx + 12, y0 + 7 * px + 14, .identity, 6)
            sx += 24
        }
        // Letters are set alight one after another.
        for (i, r) in letters.enumerated() {
            s.at(110 + 160 * i) { s in s.place(igniter, r.x0 + dx, r.y1 + dy, .identity, 5) }
        }
    }
}
