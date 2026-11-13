import SwiftUI
import CoreGraphics

/// Vector chess piece drawn in a unit square (no image assets), ported from ChessPieces.kt.
/// Rendered once per piece and pixel size into a cached `CGImage` at the screen scale.
struct ChessPieceView: View {
    let piece: ChessPiece
    let size: CGFloat
    @Environment(\.displayScale) private var displayScale

    init(_ piece: ChessPiece, _ size: CGFloat) {
        self.piece = piece
        self.size = size
    }

    var body: some View {
        let scale = max(1, displayScale)
        let px = max(1, Int((size * scale).rounded()))
        Image(decorative: ChessPieceArt.image(piece, px, scale), scale: scale)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel("\(piece.color.title) \(piece.kind.rawValue)")
    }
}

/// Renders and caches piece bitmaps per piece and pixel size.
enum ChessPieceArt {
    private struct Key: Hashable {
        let kind: PieceKind
        let color: ChessColor
        let px: Int
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Key: CGImage] = [:]
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func image(_ piece: ChessPiece, _ sizePx: Int, _ density: CGFloat) -> CGImage {
        let key = Key(kind: piece.kind, color: piece.color, px: sizePx)
        lock.lock()
        defer { lock.unlock() }
        if let image = cache[key] { return image }
        let image = render(piece, sizePx, density)
        cache[key] = image
        return image
    }

    /// Android `argb(hex, alpha)`: alpha is quantised to 8 bits like a packed colour int.
    private static func argb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        let a = CGFloat(min(255, max(0, Int((alpha * 255).rounded())))) / 255
        return CGColor(colorSpace: sRGB, components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a,
        ])!
    }

    private static func render(_ piece: ChessPiece, _ sizePx: Int, _ density: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: sizePx, height: sizePx, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // y down, origin top-left, like android.graphics.Canvas.
        ctx.translateBy(x: 0, y: CGFloat(sizePx))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        draw(ctx, piece, CGFloat(sizePx), density)
        return ctx.makeImage()!
    }

    /// Draws `piece` into a `size`×`size` square at the context origin (y down).
    static func draw(_ ctx: CGContext, _ piece: ChessPiece, _ size: CGFloat, _ density: CGFloat) {
        let isWhite = piece.color == .WHITE
        let body = bodyPath(piece.kind, size)

        // Drop shadow (SwiftUI .shadow(black 0.28, radius s*0.04, y s*0.04)).
        // Android BlurMaskFilter(radius) is a Gaussian with sigma ≈ 0.57735·radius + 0.5; Core Graphics blur ≈ 2·sigma.
        // The shape itself is drawn far off-canvas so only its shadow lands in the bitmap.
        let radius = max(0.5, size * 0.04)
        let far = size * 4 + 256
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: far, height: 0), blur: 2 * (0.57735 * radius + 0.5), color: argb(0x000000, 0.28))
        ctx.translateBy(x: -far, y: size * 0.04)
        ctx.addPath(body)
        ctx.setFillColor(argb(0x000000))
        ctx.fillPath()
        ctx.restoreGState()

        let colors = isWhite ? [argb(0xFFFFFF), argb(0xEDE6D8), argb(0xD9CFBC)] : [argb(0x5A5866), argb(0x2B2A33), argb(0x111016)]
        let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: [0, 0.5, 1])!
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()

        let outline: UInt32 = isWhite ? 0x2A2830 : 0x050508
        ctx.saveGState()
        ctx.addPath(body)
        ctx.setStrokeColor(argb(outline))
        ctx.setLineWidth(max(1 * density, size * 0.032))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.butt)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(detailPath(piece.kind, size))
        ctx.setStrokeColor(isWhite ? argb(outline, 0.85) : argb(0xFFFFFF, 0.45))
        ctx.setLineWidth(max(0.8 * density, size * 0.024))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shinePath(piece.kind, size))
        ctx.setFillColor(argb(0xFFFFFF, isWhite ? 0.55 : 0.18))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: Paths (unit square, y down). Boxes and circles run clockwise like Android `Path.Direction.CW`.

    private struct UnitPath {
        let path = CGMutablePath()
        let s: CGFloat

        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x) * s, y: CGFloat(y) * s) }

        func roundedBox(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ r: Double) {
            let l = CGFloat(x0) * s, t = CGFloat(y0) * s, rr = CGFloat(x1) * s, b = CGFloat(y1) * s
            let rad = min(CGFloat(r) * s, (rr - l) / 2, (b - t) / 2)
            path.move(to: CGPoint(x: l + rad, y: t))
            path.addLine(to: CGPoint(x: rr - rad, y: t))
            path.addArc(tangent1End: CGPoint(x: rr, y: t), tangent2End: CGPoint(x: rr, y: t + rad), radius: rad)
            path.addLine(to: CGPoint(x: rr, y: b - rad))
            path.addArc(tangent1End: CGPoint(x: rr, y: b), tangent2End: CGPoint(x: rr - rad, y: b), radius: rad)
            path.addLine(to: CGPoint(x: l + rad, y: b))
            path.addArc(tangent1End: CGPoint(x: l, y: b), tangent2End: CGPoint(x: l, y: b - rad), radius: rad)
            path.addLine(to: CGPoint(x: l, y: t + rad))
            path.addArc(tangent1End: CGPoint(x: l, y: t), tangent2End: CGPoint(x: l + rad, y: t), radius: rad)
            path.closeSubpath()
        }

        func unitCircle(_ x: Double, _ y: Double, _ r: Double) {
            let cx = CGFloat(x) * s, cy = CGFloat(y) * s, rad = CGFloat(r) * s
            let k = rad * 0.5522847498
            path.move(to: CGPoint(x: cx + rad, y: cy))
            path.addCurve(to: CGPoint(x: cx, y: cy + rad), control1: CGPoint(x: cx + rad, y: cy + k), control2: CGPoint(x: cx + k, y: cy + rad))
            path.addCurve(to: CGPoint(x: cx - rad, y: cy), control1: CGPoint(x: cx - k, y: cy + rad), control2: CGPoint(x: cx - rad, y: cy + k))
            path.addCurve(to: CGPoint(x: cx, y: cy - rad), control1: CGPoint(x: cx - rad, y: cy - k), control2: CGPoint(x: cx - k, y: cy - rad))
            path.addCurve(to: CGPoint(x: cx + rad, y: cy), control1: CGPoint(x: cx + k, y: cy - rad), control2: CGPoint(x: cx + rad, y: cy - k))
            path.closeSubpath()
        }

        func m(_ x: Double, _ y: Double) { path.move(to: pt(x, y)) }
        func l(_ x: Double, _ y: Double) { path.addLine(to: pt(x, y)) }
        /// Android `quadTo(cx, cy, x, y)`: control point (cx, cy), end point (x, y).
        func q(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double) { path.addQuadCurve(to: pt(x, y), control: pt(cx, cy)) }
        func close() { path.closeSubpath() }

        func lines(_ pts: [(Double, Double)]) {
            m(pts[0].0, pts[0].1)
            for i in 1..<pts.count { l(pts[i].0, pts[i].1) }
            close()
        }
    }

    static func bodyPath(_ kind: PieceKind, _ s: CGFloat) -> CGPath {
        let p = UnitPath(s: s)
        // Shared pedestal.
        p.roundedBox(0.2, 0.8, 0.8, 0.91, 0.04)
        p.roundedBox(0.27, 0.74, 0.73, 0.81, 0.03)
        switch kind {
        case .PAWN:
            p.m(0.36, 0.75)
            p.q(0.44, 0.47, 0.38, 0.6)
            p.l(0.56, 0.47)
            p.q(0.64, 0.75, 0.62, 0.6)
            p.close()
            p.roundedBox(0.34, 0.44, 0.66, 0.5, 0.03)
            p.unitCircle(0.5, 0.31, 0.14)
        case .ROOK:
            p.m(0.32, 0.75)
            p.l(0.35, 0.39)
            p.l(0.65, 0.39)
            p.l(0.68, 0.75)
            p.close()
            p.lines([
                (0.28, 0.4), (0.28, 0.16), (0.37, 0.16), (0.37, 0.24), (0.455, 0.24), (0.455, 0.16),
                (0.545, 0.16), (0.545, 0.24), (0.63, 0.24), (0.63, 0.16), (0.72, 0.16), (0.72, 0.4),
            ])
        case .BISHOP:
            p.m(0.37, 0.75)
            p.q(0.43, 0.58, 0.38, 0.65)
            p.l(0.57, 0.58)
            p.q(0.63, 0.75, 0.62, 0.65)
            p.close()
            p.roundedBox(0.35, 0.55, 0.65, 0.61, 0.03)
            p.m(0.5, 0.15)
            p.q(0.67, 0.41, 0.69, 0.24)
            p.q(0.5, 0.56, 0.66, 0.54)
            p.q(0.33, 0.41, 0.34, 0.54)
            p.q(0.5, 0.15, 0.31, 0.24)
            p.close()
            p.unitCircle(0.5, 0.11, 0.05)
        case .KNIGHT:
            p.m(0.3, 0.75)
            p.q(0.35, 0.5, 0.28, 0.62)
            p.q(0.4, 0.2, 0.31, 0.32)
            p.l(0.44, 0.1)
            p.l(0.5, 0.18)
            p.q(0.7, 0.35, 0.63, 0.2)
            p.q(0.79, 0.51, 0.78, 0.41)
            p.q(0.7, 0.57, 0.8, 0.58)
            p.q(0.56, 0.51, 0.62, 0.52)
            p.q(0.63, 0.75, 0.53, 0.63)
            p.close()
        case .QUEEN:
            p.lines([(0.32, 0.75), (0.36, 0.66), (0.64, 0.66), (0.68, 0.75)])
            p.roundedBox(0.31, 0.6, 0.69, 0.67, 0.03)
            p.lines([
                (0.31, 0.62), (0.2, 0.27), (0.31, 0.44), (0.35, 0.2), (0.43, 0.42), (0.5, 0.15),
                (0.57, 0.42), (0.65, 0.2), (0.69, 0.44), (0.8, 0.27), (0.69, 0.62),
            ])
            for (x, y) in [(0.2, 0.25), (0.35, 0.18), (0.5, 0.12), (0.65, 0.18), (0.8, 0.25)] {
                p.unitCircle(x, y, 0.042)
            }
        case .KING:
            p.lines([(0.32, 0.75), (0.36, 0.65), (0.64, 0.65), (0.68, 0.75)])
            p.roundedBox(0.32, 0.58, 0.68, 0.66, 0.03)
            p.m(0.33, 0.59)
            p.q(0.5, 0.3, 0.22, 0.3)
            p.q(0.67, 0.59, 0.78, 0.3)
            p.close()
            p.roundedBox(0.46, 0.05, 0.54, 0.31, 0.02)
            p.roundedBox(0.39, 0.12, 0.61, 0.19, 0.02)
        }
        return p.path
    }

    /// Inner lines that give each piece its character.
    private static func detailPath(_ kind: PieceKind, _ s: CGFloat) -> CGPath {
        let p = UnitPath(s: s)
        switch kind {
        case .ROOK:
            p.m(0.35, 0.4)
            p.l(0.65, 0.4)
        case .BISHOP:
            p.m(0.53, 0.25)
            p.l(0.6, 0.37)
        case .KNIGHT:
            p.unitCircle(0.56, 0.3, 0.018)
            p.m(0.41, 0.24)
            p.q(0.38, 0.55, 0.34, 0.4)
            p.unitCircle(0.74, 0.5, 0.008)
        case .KING:
            p.m(0.35, 0.5)
            p.l(0.65, 0.5)
        case .QUEEN:
            p.m(0.33, 0.55)
            p.l(0.67, 0.55)
        case .PAWN:
            break
        }
        return p.path
    }

    /// Soft highlight on the upper-left of each piece.
    private static func shinePath(_ kind: PieceKind, _ s: CGFloat) -> CGPath {
        let p = UnitPath(s: s)
        switch kind {
        case .PAWN: p.unitCircle(0.45, 0.26, 0.045)
        case .BISHOP: p.unitCircle(0.43, 0.3, 0.035)
        case .KING, .QUEEN: p.unitCircle(0.4, 0.48, 0.03)
        case .ROOK: p.roundedBox(0.31, 0.27, 0.35, 0.36, 0.01)
        case .KNIGHT: p.unitCircle(0.44, 0.3, 0.03)
        }
        return p.path
    }
}
