import ScreenSaver
import AppKit

/// Conway's Game of Life screen saver showing hand-composed scenes (see
/// `Scene.all`) in shuffled order, in colour. The next scene is built in the
/// background while the current one plays.
@objc(GameOfLifeView)
final class GameOfLifeView: ScreenSaverView {

    // MARK: Tuning

    /// Generations per second. Lower = calmer.
    private static let generationsPerSecond: Double = 15
    /// Fraction of each generation spent cross-fading cells (0 = hard cuts).
    private static let crossfadeFraction: Double = 0.6
    /// Cell size in points (scenes are laid out for roughly 300×200 cells).
    private static let cellSize: CGFloat = 5
    private static let previewCellSize: CGFloat = 2
    /// Opacity of the soft halo drawn under the cells.
    private static let glowOpacity: Float = 0.45

    // MARK: Scene

    private var stage: Stage?
    private var cellSize: CGFloat = 5

    // Next scene, composed (and prerolled) on a background queue.
    private struct Prepared {
        let size: CGSize
        let cellSize: CGFloat
        let stage: Stage
    }
    private var prepared: Prepared?
    private var preparing = false
    private var prepareToken = 0
    private let composerQueue = DispatchQueue(label: "GameOfLife.composer", qos: .utility)
    /// Scenes still to show before reshuffling.
    private var playlist: [Int] = []

    // Timing / transition state
    private enum Phase { case waiting, fadeIn, running, hold, fadeOut }
    private var phase: Phase = .waiting
    private var phaseStart: CFTimeInterval = 0
    private var lastGenerationTime: CFTimeInterval = 0

    // Rendering: one pixel per visible cell in `bitmap` (transparent where
    // dead), scaled up by the GPU: sharp in `lifeLayer`, smoothed underneath
    // in `glowLayer` for a soft halo.
    private let lifeLayer = CALayer()
    private let glowLayer = CALayer()
    private var bitmap: CGContext?
    private var displayLink: CADisplayLink?
    private var willStopObserver: NSObjectProtocol?

    // MARK: Lifecycle

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()

        // legacyScreenSaver on macOS 14+ keeps old instances alive; quit cleanly.
        if !isPreview {
            willStopObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screensaver.willstop"),
                object: nil, queue: .main) { _ in exit(0) }
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        // Fallback timer only; the display link drives animation when available.
        animationTimeInterval = 1.0 / 60.0
        wantsLayer = true
        layer?.backgroundColor = .black
        for (l, filter) in [(glowLayer, CALayerContentsFilter.linear), (lifeLayer, .nearest)] {
            l.magnificationFilter = filter
            l.minificationFilter = filter
            l.anchorPoint = .zero
            l.actions = ["contents": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(l)
        }
    }

    deinit {
        displayLink?.invalidate()
        if let o = willStopObserver { DistributedNotificationCenter.default().removeObserver(o) }
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
    override var isOpaque: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}

    override func startAnimation() {
        super.startAnimation()
        prepareNextScene()
        startDisplayLink()
    }

    override func stopAnimation() {
        super.stopAnimation()
        displayLink?.invalidate()
        displayLink = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isAnimating { startDisplayLink() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard stage != nil || preparing else { return }
        // Start over at the new size.
        stage = nil
        prepared = nil
        prepareToken += 1
        preparing = false
        setPhase(.waiting, CACurrentMediaTime())
        prepareNextScene()
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        advance(to: link.targetTimestamp)
    }

    override func animateOneFrame() {
        // Only used when no display link is available (e.g. not yet in a window).
        if displayLink == nil { advance(to: CACurrentMediaTime()) }
    }

    // MARK: Scenes

    private func prepareNextScene() {
        guard !preparing, prepared == nil, bounds.width > 0, bounds.height > 0 else { return }
        preparing = true
        if playlist.isEmpty { playlist = Array(Scene.all.indices).shuffled() }
        let scene = Scene.all[playlist.removeFirst()]
        let size = bounds.size
        let cell = isPreview ? Self.previewCellSize : Self.cellSize
        // Even dimensions keep mirror symmetry about the centre exact.
        let cols = max(32, Int((size.width / cell).rounded(.up)) + 1) & ~1
        let rows = max(32, Int((size.height / cell).rounded(.up)) + 1) & ~1
        let token = prepareToken
        composerQueue.async { [weak self] in
            let stage = scene.stage(cols: cols, rows: rows, seed: UInt64.random(in: 0...UInt64.max))
            DispatchQueue.main.async {
                guard let self, token == self.prepareToken else { return }
                self.preparing = false
                self.prepared = Prepared(size: size, cellSize: cell, stage: stage)
                if self.phase == .waiting { self.installPreparedScene(now: CACurrentMediaTime()) }
            }
        }
    }

    private func installPreparedScene(now: CFTimeInterval) {
        guard let p = prepared, p.size == bounds.size else {
            prepared = nil
            stage = nil
            setPhase(.waiting, now)
            prepareNextScene()
            return
        }
        prepared = nil
        stage = p.stage
        cellSize = p.cellSize
        let frame = CGRect(x: 0, y: 0, width: CGFloat(p.stage.W) * cellSize, height: CGFloat(p.stage.H) * cellSize)
        lifeLayer.frame = frame
        glowLayer.frame = frame
        bitmap = CGContext(data: nil, width: p.stage.W, height: p.stage.H, bitsPerComponent: 8,
                           bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        lastGenerationTime = now
        setPhase(.fadeIn, now)
        prepareNextScene()   // compose the next one while this one plays
    }

    // MARK: Animation

    @objc func advance(to now: CFTimeInterval) {
        guard let stage, phase != .waiting else {
            lifeLayer.opacity = 0
            glowLayer.opacity = 0
            return
        }

        // Run however many generations are due (capped so a stall can't snowball).
        let interval = 1.0 / Self.generationsPerSecond
        if now - lastGenerationTime > 0.25 { lastGenerationTime = now - interval }
        while now - lastGenerationTime >= interval {
            lastGenerationTime += interval
            stage.step()
            if phase == .running && stage.isFinished { setPhase(.hold, now) }
        }

        let elapsed = now - phaseStart
        var opacity: Double = 1
        switch phase {
        case .waiting:
            opacity = 0
        case .fadeIn:
            opacity = min(1, elapsed / 0.8)
            if opacity >= 1 { setPhase(.running, now) }
        case .running:
            break
        case .hold:
            if elapsed > 1.5 { setPhase(.fadeOut, now) }
        case .fadeOut:
            opacity = max(0, 1 - elapsed / 1.2)
            if opacity <= 0 {
                setPhase(.waiting, now)
                if prepared != nil { installPreparedScene(now: now) }
                lifeLayer.opacity = 0
                glowLayer.opacity = 0
                return
            }
        }

        let fade = Self.crossfadeFraction > 0
            ? min(1, (now - lastGenerationTime) / (interval * Self.crossfadeFraction)) : 1
        render(stage, crossfade: fade, opacity: opacity)
    }

    private func setPhase(_ p: Phase, _ now: CFTimeInterval) {
        phase = p
        phaseStart = now
    }

    private func render(_ stage: Stage, crossfade t: Double, opacity: Double) {
        guard let bitmap, let data = bitmap.data else { return }
        let w = stage.world
        // Per palette entry: fully on, fading in (being born) and fading out (dying).
        let a = w.generation > 0 ? max(0, min(1, t)) : 1
        func pixel(_ rgb: UInt32, _ k: Double) -> UInt32 {
            // Premultiplied ARGB: scale colour and alpha together.
            let s = UInt32((k * 255).rounded())
            let r = ((rgb >> 16) & 255) * s / 255, g = ((rgb >> 8) & 255) * s / 255, b = (rgb & 255) * s / 255
            return s << 24 | r << 16 | g << 8 | b
        }
        let palette = stage.palette + Array(repeating: 0xFFFFFF, count: max(0, LifeWorld.maxColors - stage.palette.count))
        let on = palette.map { pixel($0, 1) }
        let born = palette.map { pixel($0, a) }
        let dying = palette.map { pixel($0, 1 - a) }

        let dst = data.assumingMemoryBound(to: UInt32.self)
        let stride = bitmap.bytesPerRow / 4
        let cols = w.cols, M = stage.M
        w.cells.withUnsafeBufferPointer { cur in
        w.previous.withUnsafeBufferPointer { prev in
        w.colors.withUnsafeBufferPointer { col in
        w.previousColors.withUnsafeBufferPointer { pcol in
            for y in 0..<stage.H {
                let row = dst + y * stride
                let base = (y + M) * cols + M
                for x in 0..<stage.W {
                    let i = base + x
                    switch (prev[i] << 1) | cur[i] {
                    case 0: row[x] = 0
                    case 1: row[x] = born[Int(col[i])]
                    case 2: row[x] = dying[Int(pcol[i])]
                    default: row[x] = on[Int(col[i])]
                    }
                }
            }
        } } } }
        let image = bitmap.makeImage()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lifeLayer.contents = image
        glowLayer.contents = image
        lifeLayer.opacity = Float(opacity)
        glowLayer.opacity = Float(opacity) * Self.glowOpacity
        CATransaction.commit()
    }
}
