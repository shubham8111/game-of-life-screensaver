// Offline explorer for the scenes. Build with `./build.sh explore`, then:
//   build/explore selftest                       verify the stepper and every library pattern
//   build/explore scenes [dir] [name] [cols rows seed]
//                                                contact sheet per scene (6 snapshots)
//   build/explore gif [dir] [name] [cols rows seed]
//                                                animated time-lapse per scene (as in the README)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())

func naiveStep(_ c: [UInt8], _ w: Int, _ h: Int) -> [UInt8] {
    var n = c
    for y in 0..<h { for x in 0..<w {
        var k = 0
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            k += Int(c[((y + dy + h) % h) * w + (x + dx + w) % w])
        } }
        n[y * w + x] = (k == 3 || (k == 2 && c[y * w + x] == 1)) ? 1 : 0
    } }
    return n
}

/// The visible part of `stage` as an image, `scale` pixels per cell.
func screenImage(_ stage: Stage, scale: Int) -> CGImage {
    let w = stage.world, cols = stage.W * scale, rows = stage.H * scale
    let ctx = CGContext(data: nil, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let px = ctx.data!.assumingMemoryBound(to: UInt32.self)
    for y in 0..<rows { for x in 0..<cols {
        let i = (y / scale + stage.M) * w.cols + x / scale + stage.M
        px[y * cols + x] = 0xFF00_0000 | (w.cells[i] != 0 ? stage.palette[Int(w.colors[i])] : 0)
    } }
    return ctx.makeImage()!
}

/// Command-line options shared by `scenes` and `gif`.
struct SceneOptions {
    let outDir: String, only: String?, cols: Int, rows: Int, seed: UInt64
    init(defaultDir: String) {
        outDir = args.count > 1 ? args[1] : defaultDir
        only = args.count > 2 && !args[2].isEmpty ? args[2].lowercased() : nil
        cols = args.count > 3 ? Int(args[3])! : 300
        rows = args.count > 4 ? Int(args[4])! : 196
        seed = args.count > 5 ? UInt64(args[5])! : 7
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    }
    var scenes: [Scene] { Scene.all.filter { only == nil || $0.name.lowercased().hasPrefix(only!) } }
}

func fileName(_ scene: Scene) -> String { scene.name.lowercased().replacingOccurrences(of: " ", with: "-") }

func writePNG(_ img: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

/// Live cells of `w` as a normalised set, plus the bounding box origin.
func shape(_ w: LifeWorld) -> (cells: Set<Int>, x0: Int, y0: Int) {
    var pts: [(Int, Int)] = []
    for y in 0..<w.rows { for x in 0..<w.cols where w.isAlive(x, y) { pts.append((x, y)) } }
    let x0 = pts.map(\.0).min() ?? 0, y0 = pts.map(\.1).min() ?? 0
    return (Set(pts.map { ($0.1 - y0) * 10_000 + ($0.0 - x0) }), x0, y0)
}

/// Checks that `p` returns to its own shape after `period` generations,
/// displaced by `move`, and not earlier.
func checkPeriodic(_ name: String, _ p: Pattern, period: Int, move: (Int, Int) = (0, 0)) -> Bool {
    var w = LifeWorld(cols: 120, rows: 120)
    for (x, y) in p.cells { w.set(60 + x, 60 + y) }
    let start = shape(w)
    for g in 1...period {
        w.step()
        let s = shape(w)
        if s.cells == start.cells && g < period && move == (0, 0) {
            print("FAIL \(name): period \(g), expected \(period)"); return false
        }
        if g == period {
            let d = (s.x0 - start.x0, s.y0 - start.y0)
            if s.cells != start.cells || d != move {
                print("FAIL \(name): after \(period) gens shape \(s.cells == start.cells ? "same" : "differs") moved \(d)")
                return false
            }
        }
    }
    print("ok   \(name) p\(period) \(move == (0, 0) ? "" : "moves \(move)")")
    return true
}

/// Checks that a gun's own cells repeat with `period` and its stream heads `heading`.
func checkGun(_ name: String, _ p: Pattern, period: Int, heading: Heading) -> Bool {
    var w = LifeWorld(cols: 300, rows: 300)
    w.absorbingBorder = 4
    for (x, y) in p.cells { w.set(100 + x, 100 + y) }
    func region(_ w: LifeWorld) -> [Bool] {
        var r: [Bool] = []
        for y in 98...(102 + p.height) { for x in 98...(102 + p.width) { r.append(w.isAlive(x, y)) } }
        return r
    }
    for _ in 0..<(period * 3) { w.step() }
    let a = region(w)
    for _ in 0..<period { w.step() }
    guard region(w) == a else { print("FAIL \(name): not periodic with p\(period)"); return false }
    // Where did the stream go? Compare live-cell centroid outside the gun region.
    var sx = 0, sy = 0, n = 0
    for y in 0..<300 { for x in 0..<300 where w.isAlive(x, y) {
        if x < 98 || x > 102 + p.width || y < 98 || y > 102 + p.height { sx += x - (100 + p.width / 2); sy += y - (100 + p.height / 2); n += 1 }
    } }
    let dir = (n == 0 ? 0 : sx.signum(), n == 0 ? 0 : sy.signum())
    guard dir == heading.vector else { print("FAIL \(name): stream heads \(dir), expected \(heading)"); return false }
    print("ok   \(name) gun p\(period) stream \(heading)")
    return true
}

switch args.first {
case "selftest":
    var ok = true
    // Optimised stepper (incl. colour plumbing) against the naive reference.
    var rng = SplitMix64(seed: 42)
    for trial in 0..<6 {
        var w = LifeWorld(cols: 90, rows: 60)
        for _ in 0..<(trial < 3 ? 1200 : 300) {
            let x = Int.random(in: (trial < 3 ? 0 : 30)..<(trial < 3 ? 90 : 60), using: &rng)
            let y = Int.random(in: (trial < 3 ? 0 : 20)..<(trial < 3 ? 60 : 40), using: &rng)
            w.set(x, y, color: UInt8.random(in: 1...5, using: &rng))
        }
        var ref = w.cells
        for g in 0..<800 {
            w.step(); ref = naiveStep(ref, 90, 60)
            if w.cells != ref { print("FAIL stepper trial \(trial) gen \(g)"); ok = false; break }
            if zip(w.cells, w.colors).contains(where: { ($0 == 0) != ($1 == 0) }) {
                print("FAIL colour/cell mismatch trial \(trial) gen \(g)"); ok = false; break
            }
        }
    }
    print("ok   stepper")

    let P = Patterns.self
    for (name, p) in [("block", P.block), ("beehive", P.beehive), ("loaf", P.loaf), ("boat", P.boat),
                      ("ship", P.ship), ("tub", P.tub), ("pond", P.pond), ("eater", P.eater)] {
        ok = checkPeriodic(name, p, period: 1) && ok
    }
    for (name, p, period) in [("blinker", P.blinker, 2), ("toad", P.toad, 2), ("beacon", P.beacon, 2),
                              ("clock", P.clock, 2), ("pulsar", P.pulsar, 3), ("pentadecathlon", P.pentadecathlon, 15),
                              ("figureEight", P.figureEight, 8), ("trafficLight", P.trafficLight, 2),
                              ("octagon2", P.octagon2, 5), ("tumbler", P.tumbler, 14),
                              ("queenBeeShuttle", P.queenBeeShuttle, 30)] {
        ok = checkPeriodic(name, p, period: period) && ok
    }
    ok = checkPeriodic("glider", P.glider, period: 4, move: (1, 1)) && ok
    ok = checkPeriodic("lwss", P.lwss, period: 4, move: (2, 0)) && ok
    ok = checkPeriodic("mwss", P.mwss, period: 4, move: (2, 0)) && ok
    ok = checkPeriodic("hwss", P.hwss, period: 4, move: (2, 0)) && ok
    ok = checkPeriodic("copperhead", P.copperhead, period: 10, move: (1, 0)) && ok
    for h in Heading.allCases {
        let base = [.n, .e, .s, .w].contains(h) ? P.lwss : P.glider
        let v = h.vector
        let k = [.n, .e, .s, .w].contains(h) ? 2 : 1
        ok = checkPeriodic("heading \(h)", base.heading(h), period: 4, move: (v.0 * k, v.1 * k)) && ok
    }
    ok = checkGun("gosperGun", P.gosperGun, period: 30, heading: .se) && ok
    ok = checkGun("simkinGun", P.simkinGun, period: 120, heading: .se) && ok
    // Absorbing border: every ship, in every phase and heading, leaves without a trace.
    var leaks = 0
    for h in Heading.allCases {
        let base = [.n, .e, .s, .w].contains(h) ? [P.lwss, P.mwss, P.hwss] : [P.glider]
        for p in base { for phase in 0..<4 { for offset in 0..<3 {
            var w = LifeWorld(cols: 160, rows: 120)
            w.absorbingBorder = 12
            for (x, y) in p.heading(h).cells { w.set(78 + offset + x, 58 + offset * 2 + y) }
            for _ in 0..<phase { w.step() }
            for _ in 0..<700 { w.step() }
            if w.cells.contains(where: { $0 != 0 }) { leaks += 1 }
        } } }
    }
    print(leaks == 0 ? "ok   absorbing border (ships)" : "FAIL absorbing border: \(leaks) leftovers")
    ok = ok && leaks == 0
    // A gun firing into the border for a long time stays periodic.
    do {
        var w = LifeWorld(cols: 200, rows: 150)
        w.absorbingBorder = 12
        for (x, y) in P.gosperGun.cells { w.set(80 + x, 60 + y) }
        for _ in 0..<3000 { w.step() }
        let a = w.cells
        for _ in 0..<30 { w.step() }
        let good = a == w.cells
        print(good ? "ok   absorbing border (gun stream)" : "FAIL absorbing border (gun stream)")
        ok = ok && good
    }
    // The block-laying engine keeps going at c/12 (x + y of its front drops 48 per 288).
    do {
        var w = LifeWorld(cols: 700, rows: 700)
        w.absorbingBorder = 4
        for (x, y) in P.blockLayingEngine.cells { w.set(560 + x, 560 + y) }
        var fronts: [Int] = []
        for _ in 0..<6 {
            for _ in 0..<288 { w.step() }
            var m = Int.max
            for y in 0..<700 { for x in 0..<700 where w.isAlive(x, y) { m = min(m, x + y) } }
            fronts.append(m)
        }
        let good = zip(fronts, fronts.dropFirst()).allSatisfy { $0 - $1 == 48 }
        print(good ? "ok   blockLayingEngine c/12" : "FAIL blockLayingEngine fronts \(fronts)")
        ok = ok && good
    }
    print(ok ? "ALL OK" : "FAILURES")
    exit(ok ? 0 : 1)

case "scenes":
    let opt = SceneOptions(defaultDir: "build/scenes")
    let snapshots = [0, 150, 400, 900, 1800, 3000]
    let scale = 2, pad = 6, perRow = 3
    for scene in opt.scenes {
        let stage = scene.stage(cols: opt.cols, rows: opt.rows, seed: opt.seed)
        let fw = opt.cols * scale, fh = opt.rows * scale
        let sheetRows = (snapshots.count + perRow - 1) / perRow
        let sheet = CGContext(data: nil, width: perRow * (fw + pad), height: sheetRows * (fh + pad), bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        sheet.setFillColor(gray: 0.3, alpha: 1)
        sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
        let start = stage.world.generation
        var ended: Int?
        for (i, snap) in snapshots.enumerated() {
            while stage.world.generation - start < snap {
                stage.step()
                if ended == nil && stage.isFinished { ended = stage.world.generation - start }
            }
            let r = i / perRow, c = i % perRow
            sheet.draw(screenImage(stage, scale: scale),
                       in: CGRect(x: c * (fw + pad), y: (sheetRows - 1 - r) * (fh + pad), width: fw, height: fh))
        }
        writePNG(sheet.makeImage()!, "\(opt.outDir)/\(fileName(scene)).png")
        print("\(scene.name): ends at generation \(ended.map(String.init) ?? "> \(snapshots.last!)")")
    }

case "gif":
    let opt = SceneOptions(defaultDir: "docs")
    // Per scene: first generation shown and generations per frame (a multiple of
    // 4 keeps gliders and c/2 ships crisp). Each GIF is 240 frames at 25 fps.
    let windows: [String: (start: Int, step: Int)] = [
        "Crossfire": (0, 8), "Armada": (0, 8), "Lantern Garden": (1150, 6), "Supernova": (0, 8),
        "Contrails": (0, 12), "Clockwork": (1500, 6), "Big Bang": (0, 6), "Night Sky": (0, 12),
        "Monsoon": (0, 8), "Two Kingdoms": (0, 10), "LIFE": (0, 4),
    ]
    let frames = 240
    for scene in opt.scenes {
        let (start, step) = windows[scene.name] ?? (0, 8)
        let stage = scene.stage(cols: opt.cols, rows: opt.rows, seed: opt.seed)
        let path = "\(opt.outDir)/\(fileName(scene)).gif"
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                   UTType.gif.identifier as CFString, frames, nil)!
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.04]] as CFDictionary
        let origin = stage.world.generation
        for f in 0..<frames {
            while stage.world.generation - origin < start + f * step { stage.step() }
            CGImageDestinationAddImage(dest, screenImage(stage, scale: 2), frameProps)
        }
        CGImageDestinationFinalize(dest)
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        print("\(path)  \(size / 1024) KB")
    }

default:
    print("usage: explore selftest | scenes|gif [dir] [name] [cols rows seed]")
}
