import SwiftUI
import CoreText
import GameKit

// MARK: - Board view

/// The printed board: a framed two-tone grid with big numbers, ladders and snakes, all drawn in code.
/// The board is rendered once per theme/size into an image (off the main thread) so hopping tokens never redraw it.
/// `cell` is one square; the bevelled frame is drawn just outside the 10 × 10 grid without changing its layout size.
struct SnakesBoardArt: View, Equatable {
    let theme: SnakesTheme
    let cell: CGFloat
    var showsNumbers: Bool = true

    init(_ theme: SnakesTheme, _ cell: CGFloat, showsNumbers: Bool = true) {
        self.theme = theme
        self.cell = cell
        self.showsNumbers = showsNumbers
    }

    static func == (a: SnakesBoardArt, b: SnakesBoardArt) -> Bool {
        a.theme.id == b.theme.id && a.cell == b.cell && a.showsNumbers == b.showsNumbers
    }

    @Environment(\.displayScale) private var scale
    /// The last board rendered for this view; it stays up while the next key renders.
    @State private var rendered: CGImage? = nil

    var body: some View {
        let d = scale
        let cellPx = cell * d
        let key = SnakesBoardRenderer.key(theme.id, cellPx, showsNumbers)
        let image = SnakesBoardRenderer.cached(key) ?? rendered
        let theme = theme
        let showsNumbers = showsNumbers
        Color.clear
            .frame(width: cell * 10, height: cell * 10)
            .background(SnakesFrame(theme: theme, cell: cell).equatable().padding(-max(3, cell * 0.24)))
            .overlay(alignment: .topLeading) {
                if let image {
                    Image(decorative: image, scale: d)
                        .accessibilityHidden(true)
                }
            }
            .task(id: key) {
                if let hit = SnakesBoardRenderer.cached(key) {
                    rendered = hit
                    return
                }
                let img = await Task.detached(priority: .userInitiated) {
                    SnakesBoardRenderer.render(key, theme, cellPx, showsNumbers, d)
                }.value
                rendered = img
            }
    }
}

/// A thick bevelled frame just outside the grid (Compose `drawFrame` in `drawBehind`).
/// Laid out `width` larger than the grid on every side; (width, width) is the grid's top-left corner.
private struct SnakesFrame: View, Equatable {
    let theme: SnakesTheme
    let cell: CGFloat

    static func == (a: SnakesFrame, b: SnakesFrame) -> Bool { a.theme.id == b.theme.id && a.cell == b.cell }

    var body: some View {
        let theme = theme
        let cell = cell
        Canvas { ctx, size in
            let width = max(3, cell * 0.24)
            let corner = cell * 0.35 + width
            let sz = size
            let outer = CGRect(origin: .zero, size: sz)
            ctx.fill(
                Path(roundedRect: outer, cornerRadius: corner, style: .circular),
                with: .linearGradient(
                    Gradient(colors: [theme.frame.mix(.White, 0.3).color, theme.frame.color, theme.frame.mix(.Black, 0.32).color]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: sz.height)
                )
            )
            let lw1 = max(0.75, width * 0.2)
            ctx.stroke(
                Path(roundedRect: outer.insetBy(dx: lw1 / 2, dy: lw1 / 2), cornerRadius: corner - lw1 / 2, style: .circular),
                with: .linearGradient(
                    Gradient(colors: [SnakesColor.White.copy(alpha: 0.6).color, SnakesColor.White.copy(alpha: 0.05).color]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: sz.height)
                ),
                lineWidth: lw1
            )
            let lw2 = max(0.5, width * 0.08)
            ctx.stroke(
                Path(roundedRect: outer.insetBy(dx: lw2 / 2, dy: lw2 / 2), cornerRadius: corner - lw2 / 2, style: .circular),
                with: .color(theme.frame.mix(.Black, 0.5).color),
                lineWidth: lw2
            )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Renderer

/// Renders the static board into images, cached by theme, cell size and numbering.
enum SnakesBoardRenderer {
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]
    /// Least recently used first (Android `LruCache(14)`).
    private static var order: [String] = []
    private static let capacity = 14

    /// Kotlin `"${theme.id}:${cellPx.roundToInt()}:$showsNumbers"`.
    static func key(_ themeID: Int, _ cellPx: CGFloat, _ showsNumbers: Bool) -> String {
        "\(themeID):\(Kt.roundToInt(Float(cellPx))):\(showsNumbers)"
    }

    static func cached(_ key: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard let image = cache[key] else { return nil }
        touch(key)
        return image
    }

    private static func touch(_ key: String) {
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }

    private static func put(_ key: String, _ image: CGImage) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = image
        touch(key)
        while order.count > capacity {
            cache[order.removeFirst()] = nil
        }
    }

    /// Draws the board at `cell` pixels per square; `density` is pixels per point (the reference's minimum line widths).
    static func render(_ key: String, _ theme: SnakesTheme, _ cell: CGFloat, _ showsNumbers: Bool, _ density: CGFloat) -> CGImage {
        if let hit = cached(key) { return hit }
        let side = max(1, Kt.roundToInt(Float(cell * 10)))
        let image = draw(side, theme, cell, showsNumbers, density) ?? emptyImage()
        put(key, image)
        return image
    }

    /// The board as a `side` × `side` pixel image (no caching).
    static func draw(_ side: Int, _ theme: SnakesTheme, _ cell: CGFloat, _ showsNumbers: Bool, _ density: CGFloat) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Android canvas coordinates: origin top-left, y down, one unit per pixel.
        ctx.translateBy(x: 0, y: CGFloat(side))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        SnakesBoardPainter(theme, cell, showsNumbers, density).draw(ctx)
        return ctx.makeImage()
    }

    private static func emptyImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}

// MARK: - Canvas helpers (android.graphics → Core Graphics)

private enum SnakeCap { case BUTT, ROUND }

private extension CGContext {
    /// `canvas.drawPath(path, paint)` with a solid fill.
    func snakeFill(_ path: CGPath, _ color: CGColor) {
        addPath(path)
        setFillColor(color)
        fillPath()
    }

    /// `canvas.drawPath(path, stroke(color, width, cap, join))`.
    func snakeStroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat, _ cap: SnakeCap = .BUTT, join: CGLineJoin = .miter, dash: [CGFloat]? = nil) {
        saveGState()
        addPath(path)
        setStrokeColor(color)
        setLineWidth(width)
        setLineCap(cap == .ROUND ? .round : .butt)
        setLineJoin(join)
        setMiterLimit(4) // Skia's default
        if let dash { setLineDash(phase: 0, lengths: dash) }
        strokePath()
        restoreGState()
    }

    /// A path filled with a linear gradient (`LinearGradient(..., Shader.TileMode.CLAMP)`), colours evenly spaced.
    func snakeFill(_ path: CGPath, linear colors: [SnakesColor], _ start: CGPoint, _ end: CGPoint) {
        saveGState()
        addPath(path)
        clip()
        drawLinearGradient(snakeGradient(colors), start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    /// A path filled with a radial gradient (`RadialGradient(cx, cy, r, ..., CLAMP)`), colours evenly spaced.
    func snakeFill(_ path: CGPath, radial colors: [SnakesColor], _ center: CGPoint, _ radius: CGFloat) {
        saveGState()
        addPath(path)
        clip()
        drawRadialGradient(snakeGradient(colors), startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    private func snakeGradient(_ colors: [SnakesColor]) -> CGGradient {
        let n = colors.count
        let locations: [CGFloat] = (0..<n).map { n == 1 ? 0 : CGFloat($0) / CGFloat(n - 1) }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors.map(\.cg) as CFArray, locations: locations)!
    }

    /// Draws with a `BlurMaskFilter(radius, NORMAL)`: only the blurred copy lands on the canvas.
    /// The shape is drawn far off to the side and its shadow is thrown back into place.
    /// `ctmScale` is the scale already in the canvas matrix (Skia blurs respect it; Core Graphics shadows don't).
    func snakeBlurred(_ radius: CGFloat, _ color: CGColor, ctmScale: CGFloat = 1, _ body: (CGContext) -> Void) {
        let sigma = radius > 0 ? 0.57735 * radius + 0.5 : 0
        let far: CGFloat = 10_000
        saveGState()
        // The offset is in device space; move the drawing by the same device-space distance the other way.
        let inv = ctm.inverted()
        translateBy(x: -(inv.a * far), y: -(inv.b * far))
        setShadow(offset: CGSize(width: far, height: 0), blur: sigma * ctmScale / 0.475, color: color)
        setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        body(self)
        restoreGState()
    }

    /// `canvas.saveLayerAlpha(null, alpha)` … `canvas.restore()`.
    func snakeLayer(alpha: CGFloat, _ body: (CGContext) -> Void) {
        saveGState()
        setAlpha(alpha)
        beginTransparencyLayer(auxiliaryInfo: nil)
        setAlpha(1)
        body(self)
        endTransparencyLayer()
        restoreGState()
    }
}

private extension CGMutablePath {
    func addSnakeOval(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }
}

/// `Path(this).apply { offset(dx, dy) }`.
private func snakeShifted(_ path: CGPath, _ dx: CGFloat, _ dy: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: dx, y: dy)
    return path.copy(using: &t) ?? path
}

// MARK: - Painter

private final class SnakesBoardPainter {
    let theme: SnakesTheme
    /// Pixels per square.
    let cell: CGFloat
    let showsNumbers: Bool
    /// Pixels per point, for the reference's minimum line widths.
    let d: CGFloat
    /// The same cell size in Float, for the geometry loops (Android draws in Float).
    let cellF: Float

    init(_ theme: SnakesTheme, _ cell: CGFloat, _ showsNumbers: Bool, _ d: CGFloat) {
        self.theme = theme
        self.cell = cell
        self.showsNumbers = showsNumbers
        self.d = d
        cellF = Float(cell)
    }

    private func p(_ pt: BoardPoint) -> SnakePointF { SnakePointF(Float(pt.x) * cellF, Float(pt.y) * cellF) }

    private func rect(_ square: Int) -> CGRect {
        let (row, col) = SnakesBoard.cell(square)
        return CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
    }

    private func isLight(_ square: Int) -> Bool {
        let (row, col) = SnakesBoard.cell(square)
        return (row + col) % 2 == 0
    }

    func draw(_ canvas: CGContext) {
        let size = cell * 10
        let board = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: cell * 0.35, cornerHeight: cell * 0.35, transform: nil)
        canvas.saveGState()
        canvas.addPath(board)
        canvas.clip()
        drawCells(canvas)
        drawFinish(canvas)
        drawLadders(canvas)
        drawSnakes(canvas)
        // Inner lip where the frame meets the grid.
        canvas.snakeStroke(board, SnakesColor.Black.argb(theme.isDark ? 0.55 : 0.25), max(1 * d, cell * 0.09))
        canvas.restoreGState()
    }

    // MARK: Cells

    private func drawCells(_ canvas: CGContext) {
        let light = CGMutablePath()
        let strong = CGMutablePath()
        for square in 1...100 {
            if isLight(square) { light.addRect(rect(square)) } else { strong.addRect(rect(square)) }
        }
        let size = cell * 10
        canvas.snakeFill(light, linear: [theme.cellA.mix(.White, 0.25), theme.cellA], .zero, CGPoint(x: size, y: size))
        canvas.snakeFill(strong, linear: [theme.cellB.mix(.White, 0.1), theme.cellB.mix(.Black, 0.08)], .zero, CGPoint(x: size, y: size))

        // Each tile gets a soft bevel: lit on the top and left, shaded on the bottom and right.
        let bevel = max(0.5 * d, cell * 0.04)
        let lit = CGMutablePath()
        let shade = CGMutablePath()
        for square in 1...100 {
            let r = rect(square).insetBy(dx: bevel / 2, dy: bevel / 2)
            lit.move(to: CGPoint(x: r.minX, y: r.maxY)); lit.addLine(to: CGPoint(x: r.minX, y: r.minY)); lit.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            shade.move(to: CGPoint(x: r.maxX, y: r.minY)); shade.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); shade.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        canvas.snakeStroke(lit, SnakesColor.White.argb(theme.isDark ? 0.08 : 0.4), bevel)
        canvas.snakeStroke(shade, SnakesColor.Black.argb(theme.isDark ? 0.35 : 0.1), bevel)

        if !showsNumbers { return }
        let text = SnakesBoardText(max(6 * d, cell * 0.36))
        for square in 1...99 {
            let r = rect(square)
            let onLight = isLight(square)
            let line = text.line("\(square)")
            if cell >= 16 * d {
                text.draw(canvas, line, r.midX, r.midY + cell * 0.03 + text.baselineShift, SnakesColor.Black.argb(onLight ? 0.08 : 0.25))
            }
            text.draw(canvas, line, r.midX, r.midY + text.baselineShift, (onLight ? theme.numberColor : theme.numberColorB).argb())
        }
    }

    /// Square 100: a gold tile with a waving chequered flag.
    private func drawFinish(_ canvas: CGContext) {
        let r = rect(100)
        let c = cell
        canvas.snakeFill(CGPath(rect: r, transform: nil), linear: [SnakesColor(0xFFE98A), SnakesColor(0xFFB300)],
                    CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY))
        let glow = r.insetBy(dx: c * 0.12, dy: c * 0.12)
        canvas.snakeFill(CGPath(ellipseIn: glow, transform: nil), radial: [SnakesColor.White.copy(alpha: 0.6), SnakesColor.White.copy(alpha: 0)],
                    CGPoint(x: r.midX, y: r.midY), c * 0.4)

        let poleX = r.minX + c * 0.34
        let top = r.minY + c * (showsNumbers ? 0.16 : 0.22)
        let bottom = r.minY + c * (showsNumbers ? 0.66 : 0.84)
        let fw = c * 0.42
        let fh = c * 0.27
        let pole = CGMutablePath()
        pole.move(to: CGPoint(x: poleX, y: top))
        pole.addLine(to: CGPoint(x: poleX, y: bottom))
        canvas.snakeStroke(pole, SnakesColor(0x4E342E).argb(), max(1 * d, c * 0.05), .ROUND)

        let flag = CGMutablePath()
        flag.move(to: CGPoint(x: poleX, y: top))
        flag.addCurve(to: CGPoint(x: poleX + fw, y: top), control1: CGPoint(x: poleX + fw * 0.35, y: top - fh * 0.3), control2: CGPoint(x: poleX + fw * 0.65, y: top + fh * 0.3))
        flag.addLine(to: CGPoint(x: poleX + fw, y: top + fh))
        flag.addCurve(to: CGPoint(x: poleX, y: top + fh), control1: CGPoint(x: poleX + fw * 0.65, y: top + fh * 1.3), control2: CGPoint(x: poleX + fw * 0.35, y: top + fh * 0.7))
        flag.closeSubpath()
        canvas.snakeFill(flag, SnakesColor.White.cg)
        canvas.saveGState()
        canvas.addPath(flag)
        canvas.clip()
        let black = CGMutablePath()
        let sw = fw / 4
        let sh = fh / 3
        for row in -1..<4 {
            for col in 0..<4 where (row + col) % 2 == 0 {
                black.addRect(CGRect(x: poleX + CGFloat(col) * sw, y: top + CGFloat(row) * sh, width: sw, height: sh))
            }
        }
        canvas.snakeFill(black, SnakesColor(0x212121).argb())
        canvas.restoreGState()
        canvas.snakeStroke(flag, SnakesColor(0x212121).argb(), max(0.5 * d, c * 0.02))
        let knob = c * 0.05
        let knobRect = CGPath(ellipseIn: CGRect(x: poleX - knob, y: top - knob * 1.4, width: knob * 2, height: knob * 2), transform: nil)
        canvas.snakeFill(knobRect, SnakesColor(0xFFD54F).argb())
        canvas.snakeStroke(knobRect, SnakesColor(0x8D6E00).argb(), max(0.4 * d, c * 0.015))

        if showsNumbers {
            let text = SnakesBoardText(max(5 * d, c * 0.24))
            text.draw(canvas, text.line("100"), r.midX, r.minY + c * 0.83 + text.baselineShift, SnakesColor(0x7A4A00).argb())
        }
    }

    // MARK: Ladders

    private struct LadderShape {
        let rails: [CGPath]
        let rungs: CGPath
        let d: SnakePointF
        let n: SnakePointF
        let start: SnakePointF
        let total: Float
    }

    private func ladderShapes() -> [LadderShape] {
        let cell = cellF
        let half = cell * 0.2
        let extend = cell * 0.24
        return SnakesGeometry.ladderBottoms.compactMap { bottom in
            guard let top = SnakesBoard.ladders[bottom] else { return nil }
            let a = p(SnakesGeometry.center(bottom))
            let b = p(SnakesGeometry.center(top))
            let length = max(Kt.hypot(b.x - a.x, b.y - a.y), 1)
            let dv = SnakePointF((b.x - a.x) / length, (b.y - a.y) / length)
            let n = SnakePointF(-dv.y, dv.x)
            let start = SnakePointF(a.x - dv.x * extend, a.y - dv.y * extend)
            let total = length + extend * 2
            let rails: [CGPath] = [Float(-1), Float(1)].map { side in
                let path = CGMutablePath()
                path.move(to: CGPoint(x: CGFloat(start.x + n.x * half * side), y: CGFloat(start.y + n.y * half * side)))
                path.addLine(to: CGPoint(x: CGFloat(start.x + dv.x * total + n.x * half * side), y: CGFloat(start.y + dv.y * total + n.y * half * side)))
                return path
            }
            // Evenly spaced rungs about a third of a cell apart.
            let rungs = CGMutablePath()
            let margin = cell * 0.16
            let count = max(2, Kt.toInt((total - margin * 2) / (cell * 0.34)) + 1)
            let gap = (total - margin * 2) / Float(count - 1)
            for i in 0..<count {
                let along = margin + gap * Float(i)
                let px = start.x + dv.x * along
                let py = start.y + dv.y * along
                rungs.move(to: CGPoint(x: CGFloat(px + n.x * half), y: CGFloat(py + n.y * half)))
                rungs.addLine(to: CGPoint(x: CGFloat(px - n.x * half), y: CGFloat(py - n.y * half)))
            }
            return LadderShape(rails: rails, rungs: rungs, d: dv, n: n, start: start, total: total)
        }
    }

    private func drawLadders(_ canvas: CGContext) {
        let style = theme.ladder
        let light = style.rails.first ?? style.rung
        let dark = style.rails.last ?? style.rung
        let outline = dark.mix(.Black, 0.5)
        let railWidth = max(1.2 * d, cell * 0.1)
        let rungWidth = max(1 * d, cell * 0.075)
        let edge = max(0.5 * d, cell * 0.022)
        let ladders = ladderShapes()
        let black = SnakesColor.Black.cg

        // One soft shadow layer for every ladder.
        canvas.snakeLayer(alpha: CGFloat(Kt.roundToInt(Float(theme.isDark ? 0.5 : 0.26) * 255)) / 255) { c in
            c.translateBy(x: cell * 0.05, y: cell * 0.1)
            let blur = max(0.5, cell * 0.05)
            // One blurred draw per path, like the Android paint calls (overlaps composite the same way).
            for ladder in ladders {
                for rail in ladder.rails { c.snakeBlurred(blur, black) { $0.snakeStroke(rail, black, railWidth, .ROUND) } }
                c.snakeBlurred(blur, black) { $0.snakeStroke(ladder.rungs, black, rungWidth) }
            }
        }

        for ladder in ladders {
            if let glow = style.glow {
                let g = max(0.5, cell * 0.12)
                canvas.snakeBlurred(g, glow.argb(0.75)) { $0.snakeStroke(ladder.rungs, black, rungWidth + edge * 2, .ROUND) }
                for rail in ladder.rails {
                    canvas.snakeBlurred(g, glow.argb(0.75)) { $0.snakeStroke(rail, black, railWidth + edge * 2, .ROUND) }
                }
            }
            // Rungs sit under the rails.
            canvas.snakeStroke(ladder.rungs, outline.argb(), rungWidth + edge * 2, .ROUND)
            canvas.snakeStroke(ladder.rungs, style.rung.argb(), rungWidth, .ROUND)
            canvas.snakeStroke(snakeShifted(ladder.rungs, 0, -rungWidth * 0.22), SnakesColor.White.argb(0.4), rungWidth * 0.3, .ROUND)
            for rail in ladder.rails {
                // A rounded pole: dark outline, body, then a highlight towards the top left.
                canvas.snakeStroke(rail, outline.argb(), railWidth + edge * 2, .ROUND)
                canvas.snakeStroke(rail, dark.argb(), railWidth, .ROUND)
                canvas.snakeStroke(snakeShifted(rail, -railWidth * 0.12, -railWidth * 0.12), light.argb(), railWidth * 0.55, .ROUND)
                if let stripe = style.stripe {
                    canvas.snakeStroke(rail, stripe.argb(), railWidth * 0.75, dash: [cell * 0.1, cell * 0.1])
                }
                canvas.snakeStroke(snakeShifted(rail, -railWidth * 0.22, -railWidth * 0.22), SnakesColor.White.argb(0.45), railWidth * 0.18, .ROUND)
            }
            if style.knots {
                let knots = CGMutablePath()
                let cellF = cellF
                let rw = Float(railWidth)
                var along = cellF * 0.45
                while along < ladder.total - cellF * 0.1 {
                    for side in [Float(-1), Float(1)] {
                        let px = ladder.start.x + ladder.d.x * along + ladder.n.x * cellF * 0.2 * side
                        let py = ladder.start.y + ladder.d.y * along + ladder.n.y * cellF * 0.2 * side
                        knots.move(to: CGPoint(x: CGFloat(px + ladder.n.x * rw * 0.55), y: CGFloat(py + ladder.n.y * rw * 0.55)))
                        knots.addLine(to: CGPoint(x: CGFloat(px - ladder.n.x * rw * 0.55), y: CGFloat(py - ladder.n.y * rw * 0.55)))
                    }
                    along += cellF * 0.5
                }
                canvas.snakeStroke(knots, outline.argb(), max(0.8 * d, cell * 0.03))
            }
        }
    }

    // MARK: Snakes

    private struct SnakeArt {
        let body: SnakeBody
        let base: SnakesColor
        let accent: SnakesColor
        let pattern: SnakePattern
    }

    private func snakes() -> [SnakeArt] {
        // Vary the skin from snake to snake; neon boards keep their glow.
        let patterns: [SnakePattern] = theme.snakePattern == .GLOW
            ? [.GLOW]
            : [theme.snakePattern] + [SnakePattern.STRIPES, .SPOTS, .DIAMONDS].filter { $0 != theme.snakePattern }
        return SnakesGeometry.snakeHeads.enumerated().map { index, head in
            let length = SnakesGeometry.snakeLength(head)
            let spine = SnakesGeometry.snakeSpine(head, max(60, Kt.toInt(length * 36))).map(p)
            let colors = theme.snakeColors[index % theme.snakeColors.count]
            return SnakeArt(
                body: SnakeBody(spine, cellF * 0.42 * Float(min(1.0, 0.82 + length * 0.05))),
                base: colors[0],
                accent: colors.count > 1 ? colors[1] : colors[0],
                pattern: patterns[index % patterns.count]
            )
        }
    }

    private func drawSnakes(_ canvas: CGContext) {
        let snakes = snakes()
        let black = SnakesColor.Black.cg
        canvas.snakeLayer(alpha: CGFloat(Kt.roundToInt(Float(theme.isDark ? 0.55 : 0.3) * 255)) / 255) { c in
            c.translateBy(x: cell * 0.06, y: cell * 0.11)
            let blur = max(0.5, cell * 0.06)
            for snake in snakes {
                c.snakeBlurred(blur, black) { $0.snakeFill(snake.body.outline, black) }
                var t = headTransform(snake.body)
                if let head = headShape().copy(using: &t) { c.snakeBlurred(blur, black) { $0.snakeFill(head, black) } }
            }
        }
        for snake in snakes { drawBody(canvas, snake) }
        // Heads go on top of every body.
        for snake in snakes { drawHead(canvas, snake) }
    }

    private func drawBody(_ canvas: CGContext, _ snake: SnakeArt) {
        let body = snake.body
        let base = snake.base
        let accent = snake.accent
        let edge = base.mix(.Black, 0.5)
        let last = body.count - 1
        let outline = body.outline
        let cellF = cellF
        // Light comes from the top left; find which side of the body faces it.
        let facing = body.normals.reduce(Float(0)) { acc, n in acc - n.x - n.y }
        let lit: Float = facing >= 0 ? 1 : -1

        if snake.pattern == .GLOW {
            canvas.snakeBlurred(max(0.5, cell * 0.16), base.argb(0.9)) { c in c.snakeFill(outline, SnakesColor.Black.cg) }
        }
        canvas.snakeFill(
            outline,
            linear: [base.mix(.White, 0.1), base, base.mix(.Black, 0.12)],
            body.spine[0].cg, body.spine[last].cg
        )

        canvas.saveGState()
        canvas.addPath(outline)
        canvas.clip()
        canvas.snakeFill(body.strip(0, last, -0.4 * lit, -1.1 * lit), SnakesColor.Black.argb(0.2))

        switch snake.pattern {
        case .STRIPES:
            let bands = CGMutablePath()
            var s = cellF * 0.45
            while s < body.total - cellF * 0.3 {
                let i0 = body.index(s)
                bands.addPath(body.strip(i0, max(body.index(s + cellF * 0.12), i0 + 1), 1.1, -1.1))
                s += cellF * 0.34
            }
            canvas.snakeFill(bands, accent.argb())
            canvas.snakeStroke(bands, edge.argb(0.35), max(0.4 * d, cell * 0.012))
        case .SPOTS:
            let rings = CGMutablePath()
            let dots = CGMutablePath()
            var s = cellF * 0.42
            var flip: Float = 1
            while s < body.total - cellF * 0.35 {
                let i = body.index(s)
                let c = body.point(i, 0.4 * flip)
                let r = body.widths[i] * 0.2
                rings.addSnakeOval(CGFloat(c.x), CGFloat(c.y), CGFloat(r))
                dots.addSnakeOval(CGFloat(c.x), CGFloat(c.y), CGFloat(r * 0.45))
                flip = -flip
                s += cellF * 0.24
            }
            canvas.snakeFill(rings, accent.argb())
            canvas.snakeFill(dots, base.mix(.Black, 0.3).argb())
        case .DIAMONDS:
            let diamonds = CGMutablePath()
            var s = cellF * 0.4
            while s < body.total - cellF * 0.3 {
                let i = body.index(s)
                let pt = body.spine[i]
                let n = body.normals[i]
                let tx = n.y
                let ty = -n.x
                let along = cellF * 0.15 * body.widths[i] / (cellF * 0.42)
                let across = body.widths[i] * 0.36
                diamonds.move(to: CGPoint(x: CGFloat(pt.x + tx * along), y: CGFloat(pt.y + ty * along)))
                diamonds.addLine(to: CGPoint(x: CGFloat(pt.x + n.x * across), y: CGFloat(pt.y + n.y * across)))
                diamonds.addLine(to: CGPoint(x: CGFloat(pt.x - tx * along), y: CGFloat(pt.y - ty * along)))
                diamonds.addLine(to: CGPoint(x: CGFloat(pt.x - n.x * across), y: CGFloat(pt.y - n.y * across)))
                diamonds.closeSubpath()
                s += cellF * 0.3
            }
            canvas.snakeFill(diamonds, accent.argb())
            canvas.snakeStroke(diamonds, edge.argb(0.5), max(0.4 * d, cell * 0.014))
        case .GLOW:
            canvas.snakeFill(body.strip(0, last, 0.16, -0.16), accent.argb(0.9))
        }

        // Glossy back.
        let g0 = body.index(cellF * 0.25)
        let g1 = body.index(body.total - cellF * 0.35)
        canvas.snakeFill(body.strip(g0, g1, 0.2 * lit, 0.66 * lit), SnakesColor.White.argb(0.2))
        canvas.snakeFill(body.strip(g0, g1, 0.36 * lit, 0.52 * lit), SnakesColor.White.argb(0.3))
        canvas.restoreGState()

        canvas.snakeStroke(outline, edge.argb(), max(0.6 * d, cell * 0.03), join: .round)
    }

    /// Places the head on the head square, snout pointing away from the body.
    private func headTransform(_ body: SnakeBody) -> CGAffineTransform {
        let pt = body.spine[0]
        let q = body.spine[min(body.count - 1, 4)]
        // Android `Matrix.postRotate` takes Float degrees; keep that rounding.
        let degrees = Float(atan2(Double(pt.y - q.y), Double(pt.x - q.x)) * 180 / Double.pi)
        return CGAffineTransform(scaleX: 1.12, y: 1.12)
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(degrees) * .pi / 180))
            .concatenating(CGAffineTransform(translationX: CGFloat(pt.x), y: CGFloat(pt.y)))
    }

    /// A broad egg-shaped head in local units, snout along +x.
    private func headShape() -> CGPath {
        let c = cell
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -0.2 * c, y: 0))
        path.addCurve(to: CGPoint(x: 0.34 * c, y: 0), control1: CGPoint(x: -0.2 * c, y: -0.36 * c), control2: CGPoint(x: 0.32 * c, y: -0.26 * c))
        path.addCurve(to: CGPoint(x: -0.2 * c, y: 0), control1: CGPoint(x: 0.32 * c, y: 0.26 * c), control2: CGPoint(x: -0.2 * c, y: 0.36 * c))
        path.closeSubpath()
        return path
    }

    private func drawHead(_ canvas: CGContext, _ snake: SnakeArt) {
        let c = cell
        let base = snake.base
        let edge = base.mix(.Black, 0.5)
        canvas.saveGState()
        canvas.concatenate(headTransform(snake.body))

        // Forked tongue first, so it pokes out from under the snout.
        let tongue = CGMutablePath()
        tongue.move(to: CGPoint(x: 0.3 * c, y: 0)); tongue.addLine(to: CGPoint(x: 0.47 * c, y: 0)); tongue.addLine(to: CGPoint(x: 0.55 * c, y: -0.06 * c))
        tongue.move(to: CGPoint(x: 0.47 * c, y: 0)); tongue.addLine(to: CGPoint(x: 0.55 * c, y: 0.06 * c))
        canvas.snakeStroke(tongue, SnakesColor(0xE53950).argb(), max(0.8 * d, c * 0.035), .ROUND, join: .round)

        let shape = headShape()
        if snake.pattern == .GLOW {
            canvas.snakeBlurred(max(0.5, c * 0.16), base.argb(0.9), ctmScale: 1.12) { c in c.snakeFill(shape, SnakesColor.Black.cg) }
        }
        canvas.snakeFill(shape, radial: [base.mix(.White, 0.3), base, base.mix(.Black, 0.18)], CGPoint(x: 0.02 * c, y: 0), 0.34 * c)
        canvas.snakeStroke(shape, edge.argb(), max(0.6 * d, c * 0.03))

        for side in [CGFloat(-1), CGFloat(1)] {
            // Nostrils.
            let nostril = c * 0.016
            let nose = CGMutablePath()
            nose.addSnakeOval(0.27 * c, side * 0.06 * c, nostril)
            canvas.snakeFill(nose, SnakesColor.Black.argb(0.5))
            // Big cartoon eyes looking ahead.
            let r = 0.095 * c
            let cx = 0.09 * c
            let cy = side * 0.13 * c
            let eye = CGMutablePath()
            eye.addSnakeOval(cx, cy, r)
            canvas.snakeFill(eye, SnakesColor.White.cg)
            canvas.snakeStroke(eye, edge.argb(), max(0.5 * d, c * 0.022))
            let pr = r * 0.56
            let px = cx + r * 0.3
            let py = cy - side * r * 0.12
            let pupil = CGMutablePath()
            pupil.addSnakeOval(px, py, pr)
            canvas.snakeFill(pupil, SnakesColor(0x1B1B1F).argb())
            let glint = pr * 0.38
            let gx = px + pr * 0.15
            let gy = py - pr * 0.35
            let shine = CGMutablePath()
            shine.addSnakeOval(gx, gy, glint)
            canvas.snakeFill(shine, SnakesColor.White.cg)
        }
        canvas.restoreGState()
    }
}

/// Lilita One numbers drawn centred on a point like `Paint.Align.CENTER`.
private final class SnakesBoardText {
    let font: CTFont
    /// Kotlin `-(fm.ascent + fm.descent) / 2`.
    let baselineShift: CGFloat

    init(_ size: CGFloat) {
        let name = RoyalFonts.displayName as CFString
        let probe = CTFontCreateWithName(name, size, nil)
        // CoreText substitutes a default font when the name isn't registered; fall back to a bold system face like Android.
        if (CTFontCopyPostScriptName(probe) as String) == RoyalFonts.displayName {
            font = probe
        } else {
            font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? probe
        }
        baselineShift = (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
    }

    /// A line of text that takes its colour from the context, so one line serves every pass.
    func line(_ string: String) -> CTLine {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true]
        let attributed = CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary)!
        return CTLineCreateWithAttributedString(attributed)
    }

    func draw(_ ctx: CGContext, _ line: CTLine, _ x: CGFloat, _ baseline: CGFloat, _ color: CGColor) {
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x - width / 2, y: baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

/// Kotlin `PointF` (SnakesBoardArt.kt): a Float pair, like the Android painter.
private struct SnakePointF {
    let x: Float
    let y: Float

    init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    var cg: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
}

/// A snake's body sampled in board points: spine, unit normals, widths and running length.
private final class SnakeBody {
    let spine: [SnakePointF]
    let normals: [SnakePointF]
    let widths: [Float]
    let lengths: [Float]

    init(_ spine: [SnakePointF], _ width: Float) {
        self.spine = spine
        let last = spine.count - 1
        var lens: [Float] = [0]
        lens.reserveCapacity(spine.count)
        if last >= 1 {
            for i in 1...last { lens.append(lens[i - 1] + Kt.hypot(spine[i].x - spine[i - 1].x, spine[i].y - spine[i - 1].y)) }
        }
        let total = max(lens[last], 0.001)
        var ns: [SnakePointF] = []
        var ws: [Float] = []
        ns.reserveCapacity(spine.count)
        ws.reserveCapacity(spine.count)
        for i in 0...last {
            let a = spine[max(0, i - 1)]
            let b = spine[min(last, i + 1)]
            let l = max(Kt.hypot(b.x - a.x, b.y - a.y), 0.0001)
            ns.append(SnakePointF(-(b.y - a.y) / l, (b.x - a.x) / l))
            ws.append(width * SnakeBody.profile(lens[i] / total))
        }
        normals = ns
        widths = ws
        lengths = lens
    }

    /// Slim neck, full body, then a long taper to a pointed tail.
    static func profile(_ t: Float) -> Float {
        if t < 0.14 {
            let u = t / 0.14
            return 0.78 + 0.22 * u * u * (3 - 2 * u)
        }
        let base: Float = 1 - (t - 0.14) / 0.86
        return 0.1 + 0.9 * Float(pow(Double(base), 0.85))
    }

    var count: Int { spine.count }
    var total: Float { lengths.last ?? 0 }

    /// A point across the body at sample `i`: f = 1 on one edge, −1 on the other.
    func point(_ i: Int, _ f: Float) -> SnakePointF {
        SnakePointF(spine[i].x + normals[i].x * widths[i] * 0.5 * f, spine[i].y + normals[i].y * widths[i] * 0.5 * f)
    }

    /// The first sample at or beyond arc length `s` from the head.
    func index(_ s: Float) -> Int { lengths.firstIndex { $0 >= s } ?? (count - 1) }

    /// The band between two lines along the body (f0 and f1), from sample i0 to i1.
    func strip(_ i0: Int, _ i1: Int, _ f0: Float, _ f1: Float) -> CGPath {
        let path = CGMutablePath()
        if i1 <= i0 { return path }
        path.move(to: point(i0, f0).cg)
        for i in (i0 + 1)...i1 { path.addLine(to: point(i, f0).cg) }
        for i in stride(from: i1, through: i0, by: -1) { path.addLine(to: point(i, f1).cg) }
        path.closeSubpath()
        return path
    }

    lazy var outline: CGPath = strip(0, count - 1, 1, -1)
}

// MARK: - Backdrop

/// Small deterministic generator so backdrops look identical every frame.
final class SeededRandom {
    private var state: UInt64

    init(_ seed: Int64) {
        state = UInt64(bitPattern: seed) &* 6_364_136_223_846_793_005 &+ 1
    }

    func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((state >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
    }

    /// The first `count` values for a seed, computed once per theme so frames don't allocate.
    static func sequence(_ seed: Int64, _ count: Int) -> [Double] {
        let rng = SeededRandom(seed)
        return (0..<count).map { _ in rng.next() }
    }
}

/// Animated scene behind the board, matching the theme.
struct SnakesBackdropView: View {
    let theme: SnakesTheme

    init(_ theme: SnakesTheme) {
        self.theme = theme
    }

    @State private var start = Date()

    var body: some View {
        let reduce = LocalReduceMotion.current
        let theme = theme
        let randoms = SnakesBackdropView.randoms(theme.id)
        Group {
            if theme.backdrop == .DOTS || reduce {
                Canvas { ctx, size in
                    SnakesBackdropView.draw(&ctx, size, theme, randoms, 0)
                }
            } else {
                TimelineView(.animation(minimumInterval: nil, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    Canvas { ctx, size in
                        SnakesBackdropView.draw(&ctx, size, theme, randoms, t)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static let lock = NSLock()
    private static var randomCache: [Int: [Double]] = [:]

    /// The backdrop's `SeededRandom(theme.id + 7)` draws, precomputed (at most 70 × 5 per frame).
    static func randoms(_ themeID: Int) -> [Double] {
        lock.lock(); defer { lock.unlock() }
        if let hit = randomCache[themeID] { return hit }
        let values = SeededRandom.sequence(Int64(themeID + 7), 400)
        randomCache[themeID] = values
        return values
    }

    private static let white = Color.White
    private static let unitCircle = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))

    static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ theme: SnakesTheme, _ rnd: [Double], _ t: Double) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: theme.background.map(\.color)), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let pt = 1.0
        var k = 0
        func next() -> Double {
            let v = rnd[k]
            k += 1
            return v
        }
        let w = Double(size.width)
        let h = Double(size.height)
        switch theme.backdrop {
        case .STARS:
            for _ in 0..<70 {
                let x = next() * w
                let y = next() * h
                let r = (0.6 + next() * 1.8) * pt
                let twinkle = 0.45 + 0.55 * abs(sin(t * (0.6 + next()) + next() * 6))
                var c = ctx
                c.opacity = twinkle
                c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(white))
            }
        case .BUBBLES:
            for _ in 0..<26 {
                let x = next() * w
                let speed = (18 + next() * 30) * pt
                let r = (3 + next() * 9) * pt
                let y = h - fmod(t * speed + next() * h, h + 40 * pt) + 20 * pt
                let wobble = sin(t * 1.4 + next() * 6) * 6 * pt
                let cx = x + wobble
                let cy = y
                var c = ctx
                c.opacity = 0.55
                c.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(white), lineWidth: 1.2 * pt)
                let ir = r - r * 0.55
                c.opacity = 0.45
                c.fill(Path(ellipseIn: CGRect(x: cx - r * 0.3 - ir, y: cy - r * 0.3 - ir, width: ir * 2, height: ir * 2)), with: .color(white))
            }
        case .CONFETTI:
            let colors = SnakesBackdropView.confettiColors(theme)
            let piece = Path(roundedRect: CGRect(x: -4 * pt, y: -2 * pt, width: 8 * pt, height: 4 * pt), cornerRadius: 1 * pt, style: .circular)
            for i in 0..<46 {
                let x = next() * w
                let speed = (10 + next() * 18) * pt
                let y = fmod(t * speed + next() * h, h + 20 * pt) - 10 * pt
                let spin = t * (0.5 + next()) + Double(i)
                var c = ctx
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(spin))
                c.fill(piece, with: .color(colors[i % colors.count]))
            }
        case .GRID:
            let spacing = 34 * pt
            let shift = fmod(t * 12 * pt, spacing)
            let color = theme.frame.copy(alpha: 0.14).color
            // Two strokes, so crossings darken like Android's separate drawLine calls.
            var columns = Path()
            var x = 0.0
            while x <= w {
                columns.move(to: CGPoint(x: x, y: 0)); columns.addLine(to: CGPoint(x: x, y: h))
                x += spacing
            }
            ctx.stroke(columns, with: .color(color), lineWidth: 1 * pt)
            var rows = Path()
            var y = shift - spacing
            while y <= h {
                rows.move(to: CGPoint(x: 0, y: y)); rows.addLine(to: CGPoint(x: w, y: y))
                y += spacing
            }
            ctx.stroke(rows, with: .color(color), lineWidth: 1 * pt)
        case .DOTS:
            let spacing = 26 * pt
            var row = 0
            var y = 8 * pt
            let color = theme.frame.copy(alpha: 0.1).color
            var dots = Path()
            while y < h {
                var x = row % 2 == 0 ? 8 * pt : 8 * pt + spacing / 2
                while x < w {
                    dots.addEllipse(in: CGRect(x: x - 2.5 * pt, y: y - 2.5 * pt, width: 5 * pt, height: 5 * pt))
                    x += spacing
                }
                y += spacing
                row += 1
            }
            ctx.fill(dots, with: .color(color))
        }
    }

    private static var confettiCache: [Int: [Color]] = [:]

    /// `theme.snakeColors.flatten() + theme.accent` at 45% alpha, resolved once per theme.
    private static func confettiColors(_ theme: SnakesTheme) -> [Color] {
        lock.lock(); defer { lock.unlock() }
        if let hit = confettiCache[theme.id] { return hit }
        let colors = (theme.snakeColors.flatMap { $0 } + [theme.accent]).map { $0.copy(alpha: 0.45).color }
        confettiCache[theme.id] = colors
        return colors
    }
}
