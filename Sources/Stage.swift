import Foundation

/// How the cells a `Stage` sets are replicated about the screen centre.
enum Symmetry { case none, mirror4, mirror8 }

/// Rectangle in screen cells (inclusive).
struct Rect { var x0, y0, x1, y1: Int }

/// A piece of a multi-part placement (e.g. a gun and the eater for its stream).
struct Part {
    let pattern: Pattern
    let dx: Int, dy: Int
    let color: UInt8
}

enum Gun {
    case gosper, simkin

    var pattern: Pattern { self == .gosper ? Patterns.gosperGun : Patterns.simkinGun }
    /// Where an (unrotated) eater swallows the stream, `k` cells further down it.
    func eaterOffset(_ k: Int) -> (Int, Int) { self == .gosper ? (29 + k, 15 + k) : (28 + k, 32 + k) }
}

/// A scene being composed and played: the world, the screen geometry it is
/// laid out on, the whole-scene variation (mirroring) and scripted events.
/// Coordinates are screen cells; the world extends `margin` cells beyond the
/// screen on every side, where ships launch and guns hide.
final class Stage {
    static let margin = 64
    static let absorbing = 12

    let W: Int, H: Int, M: Int
    var world: LifeWorld
    var rng: SplitMix64
    let flipX: Bool, flipY: Bool
    let palette: [UInt32]
    var generations: Int
    var stagnationAfter: Int
    /// Generations simulated before the scene is first shown.
    var preroll = 0
    var symmetry: Symmetry = .none
    /// Colour override per mirror image (in `set` order), cycling if shorter.
    var imageColors: [UInt8]?
    private var events: [(generation: Int, action: (Stage) -> Void)] = []
    private var dyes: [(rect: Rect, from: UInt8, color: UInt8)] = []

    init(scene: Scene, cols: Int, rows: Int, seed: UInt64) {
        W = cols; H = rows; M = Self.margin
        rng = SplitMix64(seed: seed)
        world = LifeWorld(cols: cols + 2 * M, rows: rows + 2 * M)
        world.absorbingBorder = Self.absorbing
        world.mixColor = scene.mixColor
        for (a, b, c) in scene.mixes {
            world.mix[Int(a) * LifeWorld.maxColors + Int(b)] = c
            world.mix[Int(b) * LifeWorld.maxColors + Int(a)] = c
        }
        flipX = scene.flipX && Bool.random(using: &rng)
        flipY = scene.flipY && Bool.random(using: &rng)
        let hue = Double.random(in: -scene.hueJitter...scene.hueJitter, using: &rng)
        palette = scene.palette.map { rotateHue($0, by: hue) }
        generations = scene.generations
        stagnationAfter = scene.stagnationAfter
        scene.build(self)
        for _ in 0..<preroll { step() }
    }

    // MARK: Geometry

    var cx: Int { W / 2 }
    var cy: Int { H / 2 }
    var minDim: Int { min(W, H) }
    func x(_ f: Double) -> Int { Int((Double(W) * f).rounded()) }
    func y(_ f: Double) -> Int { Int((Double(H) * f).rounded()) }
    func random(_ r: ClosedRange<Int>) -> Int { Int.random(in: r, using: &rng) }
    func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }

    // MARK: Placing cells

    func set(_ x: Int, _ y: Int, _ color: UInt8) {
        switch symmetry {
        case .none: put(x, y, color, 0)
        case .mirror4: images(x, y, color, 0)
        case .mirror8:
            images(x, y, color, 0)
            let d = (W - H) / 2
            images(y + d, x - d, color, 4)
        }
    }

    private func images(_ x: Int, _ y: Int, _ color: UInt8, _ base: Int) {
        put(x, y, color, base)
        put(W - 1 - x, y, color, base + 1)
        put(x, H - 1 - y, color, base + 2)
        put(W - 1 - x, H - 1 - y, color, base + 3)
    }

    private func put(_ x: Int, _ y: Int, _ color: UInt8, _ image: Int) {
        let c = imageColors.map { $0[image % $0.count] } ?? color
        world.set((flipX ? W - 1 - x : x) + M, (flipY ? H - 1 - y : y) + M, color: c)
    }

    /// Places `p` (oriented) with its bounding box's top-left at (x, y).
    @discardableResult
    func place(_ p: Pattern, _ x: Int, _ y: Int, _ o: Orientation = .identity, _ color: UInt8) -> Rect {
        group([Part(pattern: p, dx: 0, dy: 0, color: color)], x, y, o)[0]
    }

    /// Places `p` (oriented) centred on (x, y).
    @discardableResult
    func center(_ p: Pattern, _ x: Int, _ y: Int, _ o: Orientation = .identity, _ color: UInt8) -> Rect {
        let q = p.oriented(o)
        return place(q, x - q.width / 2, y - q.height / 2, .identity, color)
    }

    /// Places several patterns as one rigid group, oriented as a whole, with
    /// the group's bounding box at (x, y). Returns each part's rectangle.
    @discardableResult
    func group(_ parts: [Part], _ x: Int, _ y: Int, _ o: Orientation = .identity) -> [Rect] {
        let moved = parts.map { part in part.pattern.cells.map { o.apply(part.dx + $0.0, part.dy + $0.1) } }
        let all = moved.flatMap { $0 }
        let mx = all.map(\.0).min() ?? 0, my = all.map(\.1).min() ?? 0
        return zip(parts, moved).map { part, cells in
            var r = Rect(x0: .max, y0: .max, x1: .min, y1: .min)
            for (a, b) in cells {
                let px = x + a - mx, py = y + b - my
                set(px, py, part.color)
                r = Rect(x0: min(r.x0, px), y0: min(r.y0, py), x1: max(r.x1, px), y1: max(r.y1, py))
            }
            return r
        }
    }

    /// A spaceship (any east-travelling pattern) centred on (x, y), aimed `h`.
    @discardableResult
    func ship(_ p: Pattern, _ h: Heading, _ x: Int, _ y: Int, _ color: UInt8) -> Rect {
        center(p.heading(h), x, y, .identity, color)
    }

    /// A gun at (x, y), oriented `o` (unrotated streams head south-east), with
    /// an eater `eater` cells down its stream (nil = no eater).
    @discardableResult
    func gun(_ g: Gun, _ x: Int, _ y: Int, _ o: Orientation = .identity, eater k: Int?,
             gunColor: UInt8, eaterColor: UInt8) -> (gun: Rect, eater: Rect?) {
        var parts = [Part(pattern: g.pattern, dx: 0, dy: 0, color: gunColor)]
        if let k {
            let (ex, ey) = g.eaterOffset(k)
            parts.append(Part(pattern: Patterns.eater, dx: ex, dy: ey, color: eaterColor))
        }
        let r = group(parts, x, y, o)
        return (r[0], r.count > 1 ? r[1] : nil)
    }

    /// Kills every cell in `r` (not mirrored).
    func clear(_ r: Rect) {
        let w = worldRect(r)
        for y in w.y0...w.y1 { for x in w.x0...w.x1 { world.clear(x, y) } }
    }

    /// Live cells in `r` (of colour `from`, or any when 0) are recoloured every
    /// generation. Later dyes win where they overlap. Not mirrored.
    func dye(_ r: Rect, from: UInt8 = 0, _ color: UInt8) { dyes.append((worldRect(r), from, color)) }

    private func worldRect(_ r: Rect) -> Rect {
        let (x0, x1) = flipX ? (W - 1 - r.x1, W - 1 - r.x0) : (r.x0, r.x1)
        let (y0, y1) = flipY ? (H - 1 - r.y1, H - 1 - r.y0) : (r.y0, r.y1)
        return Rect(x0: x0 + M, y0: y0 + M, x1: x1 + M, y1: y1 + M)
    }

    // MARK: Time

    /// Runs `action` once the world reaches `generation` (now, if it already has).
    func at(_ generation: Int, _ action: @escaping (Stage) -> Void) {
        if generation <= world.generation { action(self); return }
        let i = events.firstIndex { $0.generation > generation } ?? events.count
        events.insert((generation, action), at: i)
    }

    /// Set once the scene has run its course (out of time, or stagnant late enough).
    private(set) var isFinished = false

    func step() {
        world.step()
        let stagnant = world.isStagnant()
        if world.generation >= generations || (stagnant && world.generation >= stagnationAfter) { isFinished = true }
        for d in dyes { world.paint(d.rect.x0, d.rect.y0, d.rect.x1, d.rect.y1, from: d.from, color: d.color) }
        while let e = events.first, e.generation <= world.generation {
            events.removeFirst()
            let saved = (symmetry, imageColors)
            e.action(self)
            (symmetry, imageColors) = saved
        }
    }
}

/// Rotates an 0xRRGGBB colour's hue by `degrees`.
func rotateHue(_ rgb: UInt32, by degrees: Double) -> UInt32 {
    guard degrees != 0, rgb != 0 else { return rgb }
    var r = Double((rgb >> 16) & 255) / 255, g = Double((rgb >> 8) & 255) / 255, b = Double(rgb & 255) / 255
    let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
    guard d > 0 else { return rgb }
    var h: Double
    if mx == r { h = (g - b) / d } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
    h = (h * 60 + degrees).truncatingRemainder(dividingBy: 360)
    if h < 0 { h += 360 }
    let s = d / mx, v = mx
    let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
    switch Int(h / 60) {
    case 0: (r, g, b) = (c, x, 0)
    case 1: (r, g, b) = (x, c, 0)
    case 2: (r, g, b) = (0, c, x)
    case 3: (r, g, b) = (0, x, c)
    case 4: (r, g, b) = (x, 0, c)
    default: (r, g, b) = (c, 0, x)
    }
    func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, ((v + m) * 255).rounded()))) }
    return byte(r) << 16 | byte(g) << 8 | byte(b)
}

/// A hand-composed wallpaper: a palette and a `build` that lays out patterns
/// on a `Stage`, in screen-relative positions so it fits any display.
struct Scene {
    let name: String
    /// 0xRRGGBB per colour index; index 0 is the (black) background.
    let palette: [UInt32]
    /// Newborn colour when its three parents all differ.
    var mixColor: UInt8 = 1
    /// (a, b, c): a newborn of mixed a and b parents becomes c.
    var mixes: [(UInt8, UInt8, UInt8)] = []
    var generations = 4000
    /// The scene may end early on stagnation only after this generation.
    var stagnationAfter = 600
    var flipX = true, flipY = true
    var hueJitter = 10.0
    let build: (Stage) -> Void

    func stage(cols: Int, rows: Int, seed: UInt64) -> Stage {
        Stage(scene: self, cols: cols, rows: rows, seed: seed)
    }
}
