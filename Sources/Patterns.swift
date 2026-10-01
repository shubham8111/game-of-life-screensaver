import Foundation

/// A reflection/rotation of a pattern: flips are applied first, then the transpose.
struct Orientation: Equatable {
    var flipX = false, flipY = false, transpose = false

    static let identity = Orientation()
    static let flipX = Orientation(flipX: true)
    static let flipY = Orientation(flipY: true)
    static let rot180 = Orientation(flipX: true, flipY: true)
    /// Quarter turn clockwise on screen (y grows downwards): east becomes south.
    static let rot90 = Orientation(flipY: true, transpose: true)
    static let rot270 = Orientation(flipX: true, transpose: true)
    static let transpose = Orientation(transpose: true)

    func apply(_ x: Int, _ y: Int) -> (Int, Int) {
        let a = flipX ? -x : x, b = flipY ? -y : y
        return transpose ? (b, a) : (a, b)
    }
}

/// Compass headings on screen (north is up).
enum Heading: CaseIterable {
    case n, ne, e, se, s, sw, w, nw

    /// Orientation that turns a pattern travelling east (orthogonal) or
    /// south-east (diagonal) into one travelling this way.
    var orientation: Orientation {
        switch self {
        case .e, .se: return .identity
        case .w: return .flipX
        case .s: return .rot90
        case .n: return .rot270
        case .ne: return .flipY
        case .sw: return .flipX
        case .nw: return .rot180
        }
    }

    var vector: (Int, Int) {
        switch self {
        case .n: return (0, -1); case .ne: return (1, -1); case .e: return (1, 0); case .se: return (1, 1)
        case .s: return (0, 1); case .sw: return (-1, 1); case .w: return (-1, 0); case .nw: return (-1, -1)
        }
    }
}

struct Pattern {
    /// Live cells, normalised so the bounding box starts at (0, 0).
    let cells: [(Int, Int)]
    let width: Int
    let height: Int

    init(cells raw: [(Int, Int)]) {
        let x0 = raw.map(\.0).min() ?? 0, y0 = raw.map(\.1).min() ?? 0
        cells = raw.map { ($0.0 - x0, $0.1 - y0) }
        width = (cells.map(\.0).max() ?? -1) + 1
        height = (cells.map(\.1).max() ?? -1) + 1
    }

    /// Parses run-length encoded patterns as published on LifeWiki / used by
    /// Golly (header and comment lines are skipped).
    init(rle: String) {
        var cells: [(Int, Int)] = []
        var x = 0, y = 0, n = 0
        parse: for line in rle.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") || t.hasPrefix("x") { continue }
            for ch in t {
                if let d = ch.wholeNumberValue { n = n * 10 + d; continue }
                let run = max(1, n)
                n = 0
                switch ch {
                case "b", ".": x += run
                case "o", "O":
                    for i in 0..<run { cells.append((x + i, y)) }
                    x += run
                case "$": y += run; x = 0
                case "!": break parse
                default: break
                }
            }
        }
        self.init(cells: cells)
    }

    func oriented(_ o: Orientation) -> Pattern {
        o == .identity ? self : Pattern(cells: cells.map { o.apply($0.0, $0.1) })
    }

    func heading(_ h: Heading) -> Pattern { oriented(h.orientation) }
}

/// The pattern library. Every entry's period and travel are checked by
/// `explore selftest`. Spaceships travel east, diagonal movers
/// and glider guns' streams travel south-east; use `heading(_:)` to aim them.
enum Patterns {
    // Still lifes
    static let block = Pattern(rle: "2o$2o!")
    static let beehive = Pattern(rle: "b2o$o2bo$b2o!")
    static let loaf = Pattern(rle: "b2o$o2bo$bobo$2bo!")
    static let boat = Pattern(rle: "2o$obo$bo!")
    static let ship = Pattern(rle: "2o$obo$b2o!")
    static let tub = Pattern(rle: "bo$obo$bo!")
    static let pond = Pattern(rle: "b2o$o2bo$o2bo$b2o!")
    /// Eater 1 (fishhook). In this orientation it eats gliders travelling north-west
    /// that arrive at its top-left.
    static let eater = Pattern(rle: "2o$obo$2bo$2b2o!")

    // Oscillators
    static let blinker = Pattern(rle: "3o!")
    static let toad = Pattern(rle: "b3o$3o!")
    static let beacon = Pattern(rle: "2o$2o$2b2o$2b2o!")
    static let clock = Pattern(rle: "2bo$obo$bobo$bo!")
    static let pulsar = Pattern(rle: """
        2b3o3b3o2b2$o4bobo4bo$o4bobo4bo$o4bobo4bo$2b3o3b3o2b2$2b3o3b3o2b$o4bobo4bo$
        o4bobo4bo$o4bobo4bo2$2b3o3b3o!
        """)
    static let pentadecathlon = Pattern(rle: "2bo4bo$2ob4ob2o$2bo4bo!")
    static let figureEight = Pattern(rle: "3o$3o$3o$3b3o$3b3o$3b3o!")
    /// Four blinkers around an empty centre.
    static let trafficLight = Pattern(rle: "2b3o$2$o5bo$o5bo$o5bo2$2b3o!")
    static let octagon2 = Pattern(rle: "3b2o$2bo2bo$bo4bo$o6bo$o6bo$bo4bo$2bo2bo$3b2o!")
    static let tumbler = Pattern(rle: "bo5bo$obo3bobo$o2bobo2bo$2bo3bo$2b2ob2o!")
    static let queenBeeShuttle = Pattern(rle: "9bo$7bobo$6bobo$2o3bo2bo11b2o$2o4bobo11b2o$7bobo$9bo!")

    // Spaceships (travelling east)
    static let glider = Pattern(rle: "bo$2bo$3o!")          // south-east
    static let lwss = Pattern(rle: "bo2bo$o$o3bo$4o!").oriented(.flipX)
    static let mwss = Pattern(rle: "3bo$bo3bo$o$o4bo$5o!").oriented(.flipX)
    static let hwss = Pattern(rle: "3b2o$bo4bo$o$o5bo$6o!").oriented(.flipX)
    static let copperhead = Pattern(rle: "b2o2b2o$3b2o$3b2o$obo2bobo$o6bo2$o6bo$b2o2b2o$2b4o2$3b2o$3b2o!").oriented(.rot90)

    // Guns (streams travel south-east)
    static let gosperGun = Pattern(rle: """
        24bo$22bobo$12b2o6b2o12b2o$11bo3bo4b2o12b2o$2o8bo5bo3b2o$2o8bo3bob2o4bobo$
        10bo5bo7bo$11bo3bo$12b2o!
        """)
    static let simkinGun = Pattern(rle: """
        2o5b2o$2o5b2o2$4b2o$4b2o5$22b2ob2o$21bo5bo$21bo6bo2b2o$21b3o3bo3b2o$26bo4$
        20b2o$20bo$21b3o$23bo!
        """).oriented(.rot180)


    // Methuselahs and growth
    static let rPentomino = Pattern(rle: "b2o$2o$bo!")
    static let acorn = Pattern(rle: "bo$3bo$2o2b3o!")
    static let bHeptomino = Pattern(rle: "ob2o$3o$bo!")
    static let piHeptomino = Pattern(rle: "3o$obo$obo!")
    static let diehard = Pattern(rle: "6bo$2o$bo3b3o!")
    /// A fully formed block-laying switch engine: grown from the 10-cell seed
    /// `6bo$4bob2o$4bobo$4bo$2bo$obo!` and cut out after 3000 generations,
    /// without its birth debris. Travels north-west at c/12 (period 288),
    /// leaving a dotted double line of blocks.
    static let blockLayingEngine = Pattern(cells: [
        (2, 0), (1, 1), (3, 1), (1, 3), (4, 3), (3, 4), (4, 4), (4, 5), (18, 6), (19, 6), (18, 7), (19, 7),
        (1, 10), (2, 10), (3, 11), (2, 12), (3, 12), (1, 13), (2, 13), (3, 13), (19, 13), (1, 14), (2, 14),
        (19, 14), (20, 14), (26, 14), (27, 14), (0, 15), (1, 15), (2, 15), (4, 15), (19, 15), (20, 15),
        (26, 15), (27, 15), (1, 16), (5, 16), (16, 16), (17, 16), (3, 17), (6, 17), (17, 17), (3, 18),
        (4, 18), (5, 18), (18, 18), (4, 19), (5, 19), (14, 19), (15, 19), (14, 20), (15, 20), (6, 26),
        (7, 26), (6, 27), (7, 27),
    ])
}
