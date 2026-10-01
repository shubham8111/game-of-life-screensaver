import Foundation

/// A toroidal Conway's Game of Life world (B3/S23) in which every live cell
/// also carries a palette colour. Colour never affects the dynamics: survivors
/// keep theirs and a newborn inherits its three parents' (see `mix`).
struct LifeWorld {
    static let maxColors = 32

    let cols: Int
    let rows: Int
    private(set) var cells: [UInt8]
    /// The previous generation (valid once `generation > 0`).
    private(set) var previous: [UInt8]
    /// Palette index of every live cell (0 where dead), now and one generation ago.
    private(set) var colors: [UInt8]
    private(set) var previousColors: [UInt8]
    private(set) var generation = 0

    /// Colour of a newborn with two parents of colour `a` and one of colour `b`
    /// is `mix[a * maxColors + b]`; by default the majority, `a`.
    var mix: [UInt8]
    /// Colour of a newborn whose three parents all differ.
    var mixColor: UInt8 = 1
    /// Width of the outer ring in which any object lying wholly inside it is
    /// deleted, as if it had flown off to infinity. The outermost cells are
    /// also kept dead so nothing wraps around. 0 = plain torus.
    var absorbingBorder = 0

    // Stagnation detection
    private var recentHashes: [UInt64] = []
    private var populationHistory: [Int] = []
    private(set) var population = 0

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        cells = [UInt8](repeating: 0, count: cols * rows)
        previous = cells
        colors = cells
        previousColors = cells
        mix = (0..<(Self.maxColors * Self.maxColors)).map { UInt8($0 / Self.maxColors) }
    }

    mutating func set(_ x: Int, _ y: Int, color: UInt8 = 1) {
        let i = index(x, y)
        cells[i] = 1
        colors[i] = color
        boxKnown = false
    }

    mutating func clear(_ x: Int, _ y: Int) {
        let i = index(x, y)
        cells[i] = 0
        colors[i] = 0
        boxKnown = false
    }

    func isAlive(_ x: Int, _ y: Int) -> Bool { cells[index(x, y)] != 0 }

    /// Recolours live cells in the (inclusive, unwrapped) rectangle: those of colour
    /// `from`, or all of them when `from` is 0.
    mutating func paint(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, from: UInt8 = 0, color: UInt8) {
        for y in max(0, y0)...min(rows - 1, y1) {
            for i in (y * cols + max(0, x0))...(y * cols + min(cols - 1, x1)) where cells[i] != 0 && (from == 0 || colors[i] == from) {
                colors[i] = color
            }
        }
    }

    private func index(_ x: Int, _ y: Int) -> Int {
        let xx = ((x % cols) + cols) % cols
        let yy = ((y % rows) + rows) % rows
        return yy * cols + xx
    }

    /// Bounding box of live cells (inclusive), nil when unknown or empty.
    private var box: (x0: Int, y0: Int, x1: Int, y1: Int)?
    private var boxKnown = false

    mutating func step() {
        let w = cols, h = rows
        if !boxKnown { box = computeBox(); boxKnown = true }
        // Only compute the live region (plus a 1-cell margin) unless it touches an edge.
        var x0 = 0, y0 = 0, x1 = w - 1, y1 = h - 1
        var partial = false
        if let b = box, b.x0 >= 2, b.y0 >= 2, b.x1 <= w - 3, b.y1 <= h - 3 {
            (x0, y0, x1, y1) = (b.x0 - 1, b.y0 - 1, b.x1 + 1, b.y1 + 1)
            partial = true
        }
        let edge = absorbingBorder > 0
        let mixColor = self.mixColor
        let stride = Self.maxColors
        var nx0 = Int.max, ny0 = Int.max, nx1 = -1, ny1 = -1
        cells.withUnsafeBufferPointer { c in
        colors.withUnsafeBufferPointer { col in
        mix.withUnsafeBufferPointer { mx in
        previous.withUnsafeMutableBufferPointer { n in
        previousColors.withUnsafeMutableBufferPointer { ncol in
            if partial { n.update(repeating: 0); ncol.update(repeating: 0) }
            for y in y0...y1 {
                let up = ((y - 1 + h) % h) * w
                let mid = y * w
                let down = ((y + 1) % h) * w
                let edgeRow = edge && (y == 0 || y == h - 1)
                var rowAlive = false
                for x in x0...x1 {
                    let l = x == 0 ? w - 1 : x - 1
                    let r = x == w - 1 ? 0 : x + 1
                    let count = c[up + l] &+ c[up + x] &+ c[up + r]
                        &+ c[mid + l] &+ c[mid + r]
                        &+ c[down + l] &+ c[down + x] &+ c[down + r]
                    let me = c[mid + x]
                    var alive = count == 3 || (count == 2 && me == 1)
                    if alive && edge && (edgeRow || x == 0 || x == w - 1) { alive = false }
                    guard alive else {
                        n[mid + x] = 0
                        ncol[mid + x] = 0
                        continue
                    }
                    n[mid + x] = 1
                    if me != 0 {
                        ncol[mid + x] = col[mid + x]
                    } else {
                        // Birth: exactly three live neighbours; take their colours.
                        var p0: UInt8 = 0, p1: UInt8 = 0, p2: UInt8 = 0, k = 0
                        for i in [up + l, up + x, up + r, mid + l, mid + r, down + l, down + x, down + r]
                        where c[i] != 0 {
                            if k == 0 { p0 = col[i] } else if k == 1 { p1 = col[i] } else { p2 = col[i] }
                            k += 1
                        }
                        let nc: UInt8
                        if p0 == p1 { nc = p0 == p2 ? p0 : mx[Int(p0) * stride + Int(p2)] }
                        else if p0 == p2 { nc = mx[Int(p0) * stride + Int(p1)] }
                        else if p1 == p2 { nc = mx[Int(p1) * stride + Int(p0)] }
                        else { nc = mixColor }
                        ncol[mid + x] = nc
                    }
                    rowAlive = true
                    if x < nx0 { nx0 = x }
                    if x > nx1 { nx1 = x }
                }
                if rowAlive {
                    if y < ny0 { ny0 = y }
                    ny1 = y
                }
            }
        } } } } }
        box = nx1 < 0 ? nil : (nx0, ny0, nx1, ny1)
        swap(&cells, &previous)
        swap(&colors, &previousColors)
        generation += 1
        if absorbingBorder > 0 { absorb() }
    }

    // Absorbing border bookkeeping: per-pass visit stamps.
    private var visit: [UInt32] = []
    private var visitStamp: UInt32 = 0

    /// Deletes every object lying wholly within the border ring. Live cells
    /// within 2 of each other count as one object (they can interact next
    /// generation), so anything still touching the interior is left alone.
    private mutating func absorb() {
        let z = absorbingBorder, w = cols, h = rows
        if visit.count != w * h { visit = [UInt32](repeating: 0, count: w * h); visitStamp = 0 }
        visitStamp &+= 2
        let seen = visitStamp, keep = visitStamp &+ 1
        var removed = false
        var stack: [Int] = [], cluster: [Int] = []
        for y in 0..<h {
            let ringRow = y < z || y >= h - z
            var x = 0
            while x < w {
                if !ringRow && x == z { x = w - z; continue }   // skip the interior
                let i = y * w + x
                x += 1
                guard cells[i] != 0, visit[i] != seen, visit[i] != keep else { continue }
                stack.removeAll(keepingCapacity: true)
                cluster.removeAll(keepingCapacity: true)
                stack.append(i); cluster.append(i); visit[i] = seen
                var touches = false
                search: while let j = stack.popLast() {
                    let jx = j % w, jy = j / w
                    if jx >= z && jy >= z && jx < w - z && jy < h - z { touches = true; break }
                    for yy in max(0, jy - 2)...min(h - 1, jy + 2) {
                        for xx in max(0, jx - 2)...min(w - 1, jx + 2) {
                            let k = yy * w + xx
                            guard cells[k] != 0 else { continue }
                            if visit[k] == keep { touches = true; break search }
                            if visit[k] != seen { visit[k] = seen; stack.append(k); cluster.append(k) }
                        }
                    }
                }
                if touches {
                    for j in cluster { visit[j] = keep }
                } else {
                    for j in cluster { cells[j] = 0; colors[j] = 0 }
                    removed = true
                }
            }
        }
        if removed { boxKnown = false }
    }

    private func computeBox() -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
        for y in 0..<rows { for x in 0..<cols where cells[y * cols + x] != 0 {
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        } }
        return x1 < 0 ? nil : (x0, y0, x1, y1)
    }

    /// Call once per generation. True once the world has died, frozen into
    /// still lifes / short oscillators, or its population has flatlined.
    mutating func isStagnant() -> Bool {
        var hash: UInt64 = 0xcbf29ce484222325
        var pop = 0
        if let b = boxKnown ? box : computeBox() {
            cells.withUnsafeBufferPointer { c in
                for y in b.y0...b.y1 {
                    for i in (y * cols + b.x0)...(y * cols + b.x1) where c[i] != 0 {
                        hash = (hash ^ UInt64(i)) &* 0x100000001b3
                        pop += 1
                    }
                }
            }
        }
        population = pop
        if pop == 0 { return true }
        if recentHashes.contains(hash) { return true }
        recentHashes.append(hash)
        if recentHashes.count > 60 { recentHashes.removeFirst() }

        // Population flatlined (e.g. ash plus a few wandering gliders).
        populationHistory.append(pop)
        let window = 400
        if populationHistory.count > window {
            populationHistory.removeFirst(populationHistory.count - window)
            let lo = populationHistory.min()!, hi = populationHistory.max()!
            if hi - lo <= max(6, hi / 50) { return true }
        }
        return false
    }
}

/// Small, fast, seedable RNG so runs can be reproduced.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
