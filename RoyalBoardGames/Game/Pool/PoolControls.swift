import SwiftUI
import GameKit

// MARK: - Table and gestures

private enum TableMode { case Aim, Place, Call }

/// The whole screen in the game screen's `PoolTableView.space` coordinates, so the cue may be drawn past the
/// table like the Android canvas (unclipped, the table raised with zIndex).
private struct PoolScreenFrameKey: EnvironmentKey {
    static let defaultValue: CGRect = .zero
}

extension EnvironmentValues {
    var poolScreenFrame: CGRect {
        get { self[PoolScreenFrameKey.self] }
        set { self[PoolScreenFrameKey.self] = newValue }
    }
}

/// The table with its gestures: drag to aim, drag the cue ball with ball in hand, tap a pocket to call the 8.
struct PoolTableView: View {
    let session: PoolSession
    let theme: PoolTableTheme
    let cue: PoolCueStyle
    let vertical: Bool

    @State private var mode: TableMode? = nil
    @State private var callPocketIndex = -1
    @State private var grab = Vec2.ZERO
    @State private var touching = false
    @Environment(\.poolScreenFrame) private var screen

    static let space = "poolScreen"

    init(_ session: PoolSession, _ theme: PoolTableTheme, _ cue: PoolCueStyle, vertical: Bool) {
        self.session = session
        self.theme = theme
        self.cue = cue
        self.vertical = vertical
    }

    var body: some View {
        let size = session.table.size
        let geometry = PoolTableGeometry.of(size)
        let L = geometry.length + 2 * PoolTableMap.RAIL
        let W = geometry.width + 2 * PoolTableMap.RAIL
        let ratio = CGFloat(vertical ? W / L : L / W)
        let reduce = LocalReduceMotion.current
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * ratio)
            let h = w / ratio
            let scale = (vertical ? h : w) / CGFloat(L)
            let corner = 6 * scale
            // How far the piece layer may draw past the table: to the screen's edges.
            let f = geo.frame(in: .named(PoolTableView.space))
            let box = CGRect(x: f.minX + (geo.size.width - w) / 2, y: f.minY + (geo.size.height - h) / 2, width: w, height: h)
            let margin = screen.isEmpty ? EdgeInsets()
                : EdgeInsets(top: max(0, box.minY - screen.minY), leading: max(0, box.minX - screen.minX),
                             bottom: max(0, screen.maxY - box.maxY), trailing: max(0, screen.maxX - box.maxX))
            PoolTablePlate(theme, size, vertical)
                .background(RoundedRectangle(cornerRadius: corner).fill(Color.black).composeShadow(16))
                .overlay(alignment: .topLeading) {
                    PoolPieceLayer(session: session, cue: cue, vertical: vertical, reduce: reduce,
                                   table: CGSize(width: w, height: h), margin: margin)
                        .frame(width: w + margin.leading + margin.trailing, height: h + margin.top + margin.bottom)
                        .offset(x: -margin.leading, y: -margin.top)
                }
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(tableGesture(CGSize(width: w, height: h), geometry))
                }
            .frame(width: w, height: h)
            .keyframeAnimator(initialValue: 0.0, trigger: session.shakeTick) { content, v in
                content.offset(x: CGFloat(v), y: CGFloat(v) * 0.45)
            } keyframes: { _ in
                LinearKeyframe(5.0, duration: 0.04)
                LinearKeyframe(-4.0, duration: 0.05)
                LinearKeyframe(3.0, duration: 0.05)
                LinearKeyframe(-1.5, duration: 0.05)
                LinearKeyframe(0.0, duration: 0.07)
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(session, vertical))
        .accessibilityActions {
            if session.canControl {
                Button("Shoot softly") { session.setPower(0.35); session.releasePower() }
                Button("Shoot medium") { session.setPower(0.6); session.releasePower() }
                Button("Shoot hard") { session.setPower(0.9); session.releasePower() }
                Button("Turn aim left") { session.nudge(-Double.pi / 180) }
                Button("Turn aim right") { session.nudge(Double.pi / 180) }
            }
        }
    }

    private func tableGesture(_ size: CGSize, _ geometry: PoolTableGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if !touching {
                    touching = true
                    mode = nil
                }
                changed(v.location, v.startLocation, size, geometry)
            }
            .onEnded { _ in
                switch mode {
                case .Call: session.callPocket(callPocketIndex)
                case .Place: session.endPlace()
                default: break
                }
                mode = nil
                touching = false
            }
    }

    private func changed(_ pos: CGPoint, _ down: CGPoint, _ size: CGSize, _ geometry: PoolTableGeometry) {
        if !session.canControl || size.width <= 0 { return }
        let m = PoolTableMap(size, vertical, geometry)
        if mode == nil {
            let p = m.cm(down)
            let reach = max(PoolTableGeometry.R * 3, Double(30 / m.s))
            let pocket = session.needsCall ? pocketNear(geometry, p) : nil
            if let pocket {
                mode = .Call
                callPocketIndex = pocket
            } else if session.table.ballInHand && (p - session.cuePos).length < reach {
                mode = .Place
                grab = session.cuePos - p
                session.beginPlace()
            } else {
                mode = .Aim
            }
        }
        if mode == .Aim {
            session.aim(m.cm(pos))
        } else if mode == .Place {
            session.place(m.cm(pos) + grab)
        } else if mode == .Call && hypot(pos.x - down.x, pos.y - down.y) > 16 {
            // Dragged away from the pocket: aim instead.
            mode = .Aim
        }
    }
}

private func pocketNear(_ geometry: PoolTableGeometry, _ p: Vec2) -> Int? {
    let pockets = geometry.pockets
    guard let i = Array(pockets.indices).poolMinBy({ (pockets[$0].c - p).length }) else { return nil }
    return (pockets[i].c - p).length < pockets[i].r * 2.6 ? i : nil
}

enum PoolPocketName {
    static func name(_ i: Int) -> String {
        ["head left corner", "foot left corner", "foot right corner", "head right corner", "left side", "right side"][max(0, min(5, i))]
    }
}

@MainActor
private func accessibilityText(_ session: PoolSession, _ vertical: Bool) -> String {
    let t = session.table
    var parts = ["\(session.currentSeat.player.name)'s shot."]
    if t.game == .EIGHT {
        if let g = t.groupNow {
            parts.append("\(g.title.prefix(1).uppercased() + g.title.dropFirst()), \(t.left(g)) left.")
        } else {
            parts.append("Open table.")
        }
    }
    if let on = session.ballOn { parts.append("On the \(on).") }
    if t.ballInHand { parts.append("Ball in hand.") }
    // The aim as a clock face on the screen.
    let d = vertical ? CGPoint(x: sin(session.angle), y: -cos(session.angle)) : CGPoint(x: cos(session.angle), y: sin(session.angle))
    let clockAngle = atan2(Double(d.x), Double(-d.y))
    var hour = Kt.roundToInt(clockAngle / (Double.pi / 6))
    if hour <= 0 { hour += 12 }
    var aim = "Aiming at \(hour) o'clock"
    if let target = session.guide.target { aim += ", at the \(t.balls[target].n)\(session.guide.legal ? "" : ", not a legal ball")" }
    parts.append("\(aim).")
    let s = session.spin
    if s.length > 0.05 { parts.append(s.y > 0.1 ? "Follow." : (s.y < -0.1 ? "Draw." : (s.x > 0 ? "Right english." : "Left english."))) }
    if session.needsCall, let c = session.call { parts.append("Calling the \(PoolPocketName.name(c)).") }
    return parts.joined(separator: " ")
}

/// Balls, the cue, the aim guide and effects. Runs a frame loop only while something moves.
struct PoolPieceLayer: View {
    let session: PoolSession
    let cue: PoolCueStyle
    let vertical: Bool
    let reduce: Bool
    /// The table's size; the canvas reaches [margin] past it on each side.
    let table: CGSize
    let margin: EdgeInsets

    @State private var loop = GameLoop()
    @State private var settled = 0
    @Environment(\.displayScale) private var scale

    var body: some View {
        let geometry = PoolTableGeometry.of(session.table.size)
        let snap = PoolPieceSnapshot.of(session, reduce)
        // Captured inside the canvas so every display frame redraws while animating.
        let tick = loop.frame &+ settled
        let cue = cue
        let vertical = vertical
        let scale = scale
        let table = table
        let margin = margin
        Canvas { ctx, _ in
            _ = tick
            var c = ctx
            c.translateBy(x: margin.leading, y: margin.top)
            PoolPieceArt.drawPieces(c, PoolTableMap(table, vertical, geometry), snap, poolNow(), cue, scale)
        }
        .allowsHitTesting(false)
        .onAppear { run() }
        .onDisappear { loop.stop() }
        .onChange(of: session.animationEpoch) { run() }
        .onChange(of: session.playback?.start) { run() }
        .onChange(of: session.introStart) { run() }
    }

    private func run() {
        let session = session
        let loop = loop
        loop.onTick = { _ in
            if !session.animating {
                loop.stop()
                settled &+= 1
            }
        }
        loop.start()
    }
}

// MARK: - Controls

private let PowerGreen = poolHex(0x34C759)
private let PowerAmber = poolHex(0xFF9500)
private let PowerRed = poolHex(0xFF3B30)

/// Pull the cue down the bar and let go to shoot; slide it back to the top to cancel.
struct PoolPowerBar: View {
    let session: PoolSession
    let cue: PoolCueStyle
    let vertical: Bool

    @State private var dragging = false
    @State private var allowed = false
    @GestureState private var pressing = false
    @Environment(\.displayScale) private var scale

    init(_ session: PoolSession, _ cue: PoolCueStyle, vertical: Bool) {
        self.session = session
        self.cue = cue
        self.vertical = vertical
    }

    var body: some View {
        let enabled = session.canControl
        let p = session.power
        let pulling = session.pulling
        let vertical = vertical
        let cue = cue
        let scale = scale
        GeometryReader { geo in
            let thick = vertical ? geo.size.width : geo.size.height
            let length = vertical ? geo.size.height : geo.size.width
            let hot = p > 0.75 ? PowerRed : (p > 0.45 ? PowerAmber : PowerGreen)
            let shape = RoundedRectangle(cornerRadius: thick / 2, style: .circular)
            ZStack(alignment: vertical ? .bottom : .trailing) {
                shape.fill(LinearGradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
                Canvas { ctx, size in
                    let inset: CGFloat = 6
                    let full = (vertical ? size.height : size.width) - 2 * inset
                    // The fill grows from the start of the bar as the cue is pulled.
                    let fill = full * CGFloat(p)
                    let rect = vertical ? CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: fill)
                        : CGRect(x: inset, y: inset, width: fill, height: size.height - 2 * inset)
                    if fill > 1 {
                        let radius = (vertical ? rect.width : rect.height) / 2
                        ctx.fill(Path(roundedRect: rect, cornerRadius: radius, style: .circular),
                                 with: .linearGradient(Gradient(colors: [PowerGreen.color, poolHex(0xFFCC00).color, PowerRed.color]),
                                                       startPoint: CGPoint(x: inset, y: inset),
                                                       endPoint: vertical ? CGPoint(x: inset, y: inset + full) : CGPoint(x: inset + full, y: inset)))
                    }
                    for k in 1..<10 {
                        let v = inset + full * CGFloat(k) / 10
                        var tick = Path()
                        if vertical {
                            tick.move(to: CGPoint(x: size.width - 9, y: v)); tick.addLine(to: CGPoint(x: size.width - 4, y: v))
                        } else {
                            tick.move(to: CGPoint(x: v, y: size.height - 9)); tick.addLine(to: CGPoint(x: v, y: size.height - 4))
                        }
                        ctx.stroke(tick, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
                    }
                    // The cue itself slides with the pull, tip first.
                    let offset = inset + full * CGFloat(p)
                    let tip = vertical ? CGPoint(x: size.width / 2, y: offset + 4) : CGPoint(x: offset + 4, y: size.height / 2)
                    let len = vertical ? size.height : size.width
                    let th = vertical ? size.width : size.height
                    PoolCueSprites.drawCue(ctx, tip, vertical ? CGPoint(x: 0, y: -1) : CGPoint(x: -1, y: 0), len * 1.6, th * 0.22, cue, scale: scale)
                }
                .clipShape(shape)
                if pulling {
                    Text("\(Int(p * 100))%", style: bodyStyle(11, .Black, Color.white))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(hot.color))
                        .offset(x: vertical ? 0 : -7, y: vertical ? -6 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .bottom : .trailing)
                }
            }
            .contentShape(Rectangle())
            .gesture(powerGesture(length))
        }
        .opacity(enabled || pulling ? 1 : 0.45)
        .animation(.tween(200), value: enabled || pulling)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power")
        .accessibilityValue("\(Int(p * 100)) percent")
        .onChange(of: pressing) { _, now in
            // The touch was taken away mid-pull (not a release): put the cue back without shooting.
            if !now {
                DispatchQueue.main.async {
                    if allowed {
                        allowed = false
                        dragging = false
                        session.cancelPull()
                    }
                }
            }
        }
    }

    private func powerGesture(_ length: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($pressing) { _, state, _ in state = true }
            .onChanged { v in
                if !dragging {
                    dragging = true
                    allowed = session.canControl
                    if allowed { session.setPower(0.0) }
                }
                guard allowed else { return }
                let t = vertical ? v.location.y - v.startLocation.y : v.location.x - v.startLocation.x
                session.setPower(Double(max(0, t) / (length * 0.8)))
            }
            .onEnded { _ in
                let shoot = allowed
                allowed = false
                dragging = false
                if shoot { session.releasePower() }
            }
    }
}

/// A ribbed wheel for the last tenths of a degree.
struct PoolFineWheel: View {
    let session: PoolSession
    let vertical: Bool

    @State private var roll: CGFloat = 0
    @State private var last: CGFloat? = nil
    @State private var allowed = false

    init(_ session: PoolSession, vertical: Bool) {
        self.session = session
        self.vertical = vertical
    }

    var body: some View {
        let enabled = session.canControl
        let roll = roll
        let vertical = vertical
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let corner = (vertical ? size.width : size.height) / 2
            ctx.fill(Path(roundedRect: rect, cornerRadius: corner, style: .circular), with: .color(poolHex(0x1A1A1E).color))
            var inner = ctx
            inner.clip(to: Path(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: max(0, corner - 3), style: .circular))
            let length = vertical ? size.height : size.width
            let spacing: CGFloat = 7
            var k = -spacing + roll.truncatingRemainder(dividingBy: spacing)
            while k < length + spacing {
                // Ridges bunch towards the edges, like a cylinder.
                let u = Double(k / length * 2 - 1)
                let warped = CGFloat((sin(u * Double.pi / 2) + 1) / 2 * Double(length))
                let alpha = min(1, max(0, 0.18 + 0.3 * (1 - abs(u))))
                var line = Path()
                if vertical {
                    line.move(to: CGPoint(x: 6, y: warped)); line.addLine(to: CGPoint(x: size.width - 6, y: warped))
                } else {
                    line.move(to: CGPoint(x: warped, y: 6)); line.addLine(to: CGPoint(x: warped, y: size.height - 6))
                }
                inner.stroke(line, with: .color(Color.white.opacity(alpha)), lineWidth: 2)
                k += spacing
            }
            let shade = [Color.black.opacity(0.7), Color.clear, Color.white.opacity(0.08), Color.clear, Color.black.opacity(0.7)]
            inner.fill(Path(rect), with: .linearGradient(Gradient(colors: shade), startPoint: .zero,
                                                        endPoint: vertical ? CGPoint(x: 0, y: size.height) : CGPoint(x: size.width, y: 0)))
            ctx.stroke(Path(roundedRect: CGRect(x: 0.75, y: 0.75, width: size.width - 1.5, height: size.height - 1.5), cornerRadius: corner, style: .circular),
                       with: .color(Color.white.opacity(0.3)), lineWidth: 1.5)
        }
        .opacity(enabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    let now = vertical ? v.location.y : v.location.x
                    if last == nil {
                        allowed = session.canControl
                        last = vertical ? v.startLocation.y : v.startLocation.x
                    }
                    guard allowed, let prev = last else { return }
                    let d = now - prev
                    last = now
                    self.roll += d
                    session.nudge(Double(d) * 0.0012)
                }
                .onEnded { _ in
                    last = nil
                    allowed = false
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fine aim")
        .accessibilityActions {
            Button("Turn a tenth of a degree left") { session.nudge(-0.1 * Double.pi / 180) }
            Button("Turn a tenth of a degree right") { session.nudge(0.1 * Double.pi / 180) }
        }
    }
}

/// A white ball with a red dot where the tip will strike.
struct PoolSpinButton: View {
    let session: PoolSession
    let size: CGFloat
    let onClick: () -> Void

    init(_ session: PoolSession, _ size: CGFloat, _ onClick: @escaping () -> Void) {
        self.session = session
        self.size = size
        self.onClick = onClick
    }

    var body: some View {
        let spin = session.spin
        let size = size
        Canvas { ctx, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let r = size * 0.42
            ctx.fill(PoolArt.circle(c, r), with: .radialGradient(Gradient(colors: [Color.white, poolHex(0xD8D6CE).color]),
                                                                 center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
            ctx.stroke(PoolArt.circle(c, r * 0.62), with: .color(Color.black.opacity(0.15)), lineWidth: 1)
            let k = r * 0.62 / 0.5
            let dot = CGPoint(x: c.x + CGFloat(spin.x) * k, y: c.y - CGFloat(spin.y) * k)
            ctx.fill(PoolArt.circle(dot, r * 0.2), with: .color(poolHex(0xE0242B).color))
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Color.black.opacity(0.35)))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
        .frame(minWidth: 48, minHeight: 48)
        .opacity(session.canControl ? 1 : 0.6)
        .pressable(sound: nil, pressedScale: 0.9, onClick: onClick)
        .accessibilityLabel("Spin")
        .accessibilityValue(spinText(spin))
    }
}

func spinText(_ s: Vec2) -> String {
    if s.length < 0.05 { return "Centre ball" }
    var parts: [String] = []
    if s.y > 0.08 { parts.append("follow") } else if s.y < -0.08 { parts.append("draw") }
    if s.x > 0.08 { parts.append("right english") } else if s.x < -0.08 { parts.append("left english") }
    return parts.joined(separator: " and ").split(separator: " ", omittingEmptySubsequences: false)
        .map { w in w.prefix(1).uppercased() + w.dropFirst() }
        .joined(separator: " ")
}

/// The return: pocketed balls roll down and stack.
struct PoolChute: View {
    let session: PoolSession
    let vertical: Bool

    init(_ session: PoolSession, vertical: Bool) {
        self.session = session
        self.vertical = vertical
    }

    var body: some View {
        let reduce = LocalReduceMotion.current
        let chute = session.chute
        GeometryReader { geo in
            let length = vertical ? geo.size.height : geo.size.width
            let thick = vertical ? geo.size.width : geo.size.height
            let ball = max(10, thick - 8)
            // Balls overlap a little once the chute is full.
            let count = max(1, chute.count)
            let gap = min(1, (length - 8 - ball) / CGFloat(max(1, count - 1)) - ball)
            let shape = RoundedRectangle(cornerRadius: thick / 2, style: .circular)
            ZStack(alignment: .topLeading) {
                shape.fill(LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                ForEach(chute, id: \.self) { n in
                    // Along the chute: from the bottom (portrait: the start) to the newest ball.
                    let index = chute.firstIndex(of: n) ?? 0
                    let slot = 4 + CGFloat(index) * (ball + gap)
                    let target = vertical ? length - ball - slot : slot
                    PoolChuteBall(n: n, size: ball, target: target, start: vertical ? -ball : length, vertical: vertical, thick: thick, reduce: reduce)
                }
            }
            .clipShape(shape)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pocketed")
        .accessibilityValue(chute.isEmpty ? "None yet" : chute.map { String($0) }.joined(separator: ", "))
    }
}

private struct PoolChuteBall: View {
    let n: Int
    let size: CGFloat
    let target: CGFloat
    let start: CGFloat
    let vertical: Bool
    let thick: CGFloat
    let reduce: Bool

    @State private var pos: CGFloat? = nil
    @State private var fade: Double = 0

    var body: some View {
        let p = pos ?? (reduce ? target : start)
        PoolMiniBall(n, size)
            .opacity(fade)
            .offset(x: vertical ? (thick - size) / 2 : p, y: vertical ? p : (thick - size) / 2)
            .onAppear {
                if reduce {
                    pos = target
                } else {
                    // New balls roll in from the top (or the far end) of the return.
                    withAnimation(.compose(dampingRatio: 0.72, stiffness: 130)) { pos = target }
                }
                withAnimation(.tween(reduce ? 200 : 260)) { fade = 1 }
            }
            .onChange(of: target) { _, t in
                if reduce { pos = t } else { withAnimation(.compose(dampingRatio: 0.72, stiffness: 130)) { pos = t } }
            }
    }
}

/// "On the 3" in 9-Ball, "On the 8" once a group is cleared.
struct PoolBallOnPill: View {
    let session: PoolSession

    init(_ session: PoolSession) { self.session = session }

    var body: some View {
        let on = session.ballOn
        let g = session.table.groupNow
        HStack(spacing: 5) {
            if let on {
                PoolMiniBall(on, 20)
                Text("ON THE \(on)", style: bodyStyle(11, .Black, Color.white).copy(letterSpacing: 0.5)).lineLimit(1)
            } else if session.table.game == .EIGHT && g == nil {
                Text("OPEN TABLE", style: bodyStyle(11, .Black, Color.white.opacity(0.85)).copy(letterSpacing: 0.5)).lineLimit(1)
            } else if let g {
                Text(g.title.uppercased(), style: bodyStyle(11, .Black, Color.white).copy(letterSpacing: 0.5)).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Players

/// Two players: panels either side of the score. Three or four: compact chips.
struct PoolPlayersBar: View {
    let session: PoolSession
    let compact: Bool

    init(_ session: PoolSession, compact: Bool) {
        self.session = session
        self.compact = compact
    }

    var body: some View {
        let seats = session.config.seats
        HStack(spacing: 6) {
            if seats.count == 2 {
                PoolPanel(session: session, index: 0, trailing: false)
                if compact { PoolScorePill(session, inline: false) }
                PoolPanel(session: session, index: 1, trailing: true)
            } else {
                ForEach(seats.indices, id: \.self) { i in
                    PoolChip(session: session, index: i, compact: compact)
                }
                if compact { PoolScorePill(session, inline: false) }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

@MainActor
private func active(_ session: PoolSession, _ index: Int) -> Bool {
    index == session.table.turn && session.phase != .OVER && session.phase != .BETWEEN
}

private struct PoolPanel: View {
    let session: PoolSession
    let index: Int
    let trailing: Bool

    var body: some View {
        let seat = session.config.seats[index]
        let unit = session.table.unit(index)
        let on = active(session, index)
        let glow: Double = on ? 1 : 0
        let colour = seat.player.color
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        HStack(spacing: 0) {
            if !trailing {
                PoolPlayerAvatar(session: session, index: index, size: 40)
                Spacer().frame(width: 7)
            }
            VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if trailing { PoolWins(session: session, unit: unit) }
                    Text(seat.player.name, style: bodyStyle(14, .ExtraBold, Color.white)).lineLimit(1).truncationMode(.tail)
                    if !trailing { PoolWins(session: session, unit: unit) }
                }
                PoolGroupBalls(session: session, seat: index, size: 11)
            }
            if trailing {
                Spacer().frame(width: 7)
                PoolPlayerAvatar(session: session, index: index, size: 40)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: trailing ? .trailing : .leading)
        .background(shape.fill(Color.black.opacity(0.16 + 0.18 * glow)))
        .overlay(shape.strokeBorder(colour.opacity(glow), lineWidth: 2))
        .clipShape(shape)
        // The coloured elevation glow (Compose `shadow(8.dp * glow, spotColor = colour)`), outside the translucent panel.
        .background(shape.stroke(colour.opacity(0.55 * glow), lineWidth: 3).blur(radius: 4 * glow))
        .animation(.compose(dampingRatio: 0.8, stiffness: 400), value: on)
    }
}

private struct PoolChip: View {
    let session: PoolSession
    let index: Int
    let compact: Bool

    var body: some View {
        let seat = session.config.seats[index]
        let unit = session.table.unit(index)
        let on = active(session, index)
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        HStack(spacing: 6) {
            PoolPlayerAvatar(session: session, index: index, size: compact ? 32 : 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(seat.player.name, style: bodyStyle(11, .ExtraBold, Color.white)).lineLimit(1).truncationMode(.tail)
                if session.table.teams {
                    Text(session.unitName(unit).uppercased(), style: bodyStyle(8, .Black, Color.white.opacity(0.6))).lineLimit(1)
                }
                PoolWins(session: session, unit: unit)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(shape.fill(Color.black.opacity(on ? 0.34 : 0.16)))
        .overlay(shape.strokeBorder(on ? seat.player.color : Color.clear, lineWidth: 2))
        .clipShape(shape)
    }
}

private struct PoolPlayerAvatar: View {
    let session: PoolSession
    let index: Int
    let size: CGFloat

    var body: some View {
        let on = active(session, index)
        PoolAvatar(session.config.seats[index], size, active: on, clockEnds: on ? session.clockEnds : nil, seconds: session.config.options.shotClock)
    }
}

/// A seat's group as seven mini balls that dim as they drop, then the 8.
private struct PoolGroupBalls: View {
    let session: PoolSession
    let seat: Int
    let size: CGFloat

    var body: some View {
        let t = session.table
        let unit = t.unit(seat)
        let g: PoolGroup? = t.game == .EIGHT ? t.groups[unit] : nil
        HStack(spacing: 0) {
            if let g {
                if t.left(g) == 0 {
                    PoolMiniBall(8, size + 4)
                        .shadow(color: poolHex(0xFFD24D).color.opacity(0.6), radius: 3.3)
                    Text("ON THE 8", style: bodyStyle(9, .Black, poolHex(0xFFE27A).color).copy(letterSpacing: 0.5))
                        .lineLimit(1)
                        .padding(.leading, 3)
                } else {
                    ForEach(g.numbers, id: \.self) { n in PoolMiniBall(n, size, dim: t.ball(n) == nil) }
                }
            } else if t.game == .EIGHT {
                Text("OPEN TABLE", style: bodyStyle(9, .Black, Color.white.opacity(0.6)).copy(letterSpacing: 0.5)).lineLimit(1)
            } else {
                Text("\(t.stats[seat].potted) potted", style: bodyStyle(10, .ExtraBold, Color.white.opacity(0.75))).lineLimit(1)
            }
        }
        .frame(height: size + 4)
    }
}

/// Racks won in a race, as pips.
private struct PoolWins: View {
    let session: PoolSession
    let unit: Int

    var body: some View {
        let m = session.match
        if m.target > 1 {
            HStack(spacing: 2) {
                ForEach(0..<m.target, id: \.self) { k in
                    Circle().fill(k < m.wins[unit] ? poolHex(0xFFD24D).color : Color.white.opacity(0.2)).frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(m.wins[unit]) racks won")
        }
    }
}

struct PoolScorePill: View {
    let session: PoolSession
    let inline: Bool

    @State private var bump: CGFloat = 1

    init(_ session: PoolSession, inline: Bool) {
        self.session = session
        self.inline = inline
    }

    var body: some View {
        let m = session.match
        var parts = [m.game.title.uppercased()]
        if m.teams { parts.append("2 V 2") }
        if m.target > 1 { parts.append("RACE TO \(m.target)") }
        let top = parts.joined(separator: " · ")
        let score = (m.target > 1 && m.units == 2) ? "\(m.wins[0]) – \(m.wins[1])" : "RACK \(m.rack)"
        let wins = m.wins.reduce(0, +)
        return Group {
            if inline {
                HStack(spacing: 6) {
                    Text(top, style: bodyStyle(9, .ExtraBold, Color.white.opacity(0.7)).copy(letterSpacing: 0.8)).lineLimit(1)
                    Text(score, style: displayStyle(15, poolHex(0xFFE27A).color)).lineLimit(1).scaleEffect(bump)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .fixedSize(horizontal: true, vertical: false)
            } else {
                VStack(spacing: 1) {
                    Text(top, style: bodyStyle(9, .ExtraBold, Color.white.opacity(0.7)).copy(letterSpacing: 1)).lineLimit(1)
                    Text(score, style: displayStyle(17, poolHex(0xFFE27A).color)).lineLimit(1).scaleEffect(bump)
                    if let on = session.ballOn {
                        HStack(spacing: 3) {
                            PoolMiniBall(on, 13)
                            Text("ON THE \(on)", style: bodyStyle(8, .Black, Color.white.opacity(0.85))).lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .fixedSize()
            }
        }
        .onAppear { pop() }
        .onChange(of: wins) { pop() }
    }

    private func pop() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { bump = 1.25 }
        DispatchQueue.main.async {
            withAnimation(.compose(dampingRatio: 0.45, stiffness: 500)) { bump = 1 }
        }
    }
}

/// A player disc with the shot clock ring and a CPU tag.
struct PoolAvatar: View {
    let seat: PoolSeat
    let size: CGFloat
    var active: Bool = false
    var clockEnds: Double? = nil
    var seconds: Int = 0

    init(_ seat: PoolSeat, _ size: CGFloat, active: Bool = false, clockEnds: Double? = nil, seconds: Int = 0) {
        self.seat = seat
        self.size = size
        self.active = active
        self.clockEnds = clockEnds
        self.seconds = seconds
    }

    var body: some View {
        let ring: Double = active ? 1 : 0
        let c = seat.player.color
        ZStack {
            ZStack {
                Circle().fill(LinearGradient(colors: [lerp(c, Color.White, Float(0.15)), lerp(c, Color.Black, Float(0.2))], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(lerp(Color.white.copy(alpha: 0.85), poolHex(0xFFE45C).color, ring), lineWidth: 2 + ring)
                Text(verbatim: seat.player.avatar).font(.system(size: size * 0.52))
            }
            .frame(width: size, height: size)
            .shadow(color: poolHex(0xFFE45C).color.opacity(0.6 * ring), radius: 8 * ring * 0.55)
            .animation(.compose(dampingRatio: 0.7, stiffness: 500), value: active)
            if let clockEnds, seconds > 0 {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let left = max(0.0, clockEnds - poolNow()) / Double(seconds)
                    Canvas { ctx, s in
                        let w: CGFloat = 3.5
                        let arc = RoyalDraw.arcPath(-90, 360 * left, false, CGRect(x: w / 2, y: w / 2, width: s.width - w, height: s.height - w))
                        ctx.stroke(arc, with: .color((left < 0.3 ? PowerRed : PowerGreen).color), style: StrokeStyle(lineWidth: w, lineCap: .round))
                    }
                }
                .frame(width: size + 8, height: size + 8)
                .allowsHitTesting(false)
            }
            if seat.isBot {
                Text("CPU", style: bodyStyle(7, .Black, Color.white))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(height: 13)
                    .background(Capsule().fill(poolHex(0x1C1B29).color))
                    .offset(y: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: size + 8, height: size + 8)
    }
}

// MARK: - Around the table

struct PoolBackdrop: View {
    let theme: PoolTableTheme

    init(_ theme: PoolTableTheme) { self.theme = theme }

    var body: some View {
        let theme = theme
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: theme.backdrop.map { $0.color }), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            // A lamp over the table.
            let lamp: CGFloat = 520
            let lit = theme.cloth[0].alpha(0.28).color
            ctx.fill(Path(rect), with: .radialGradient(Gradient(stops: [.init(color: lit, location: 0), .init(color: lit, location: 10.0 / 520.0),
                                                                       .init(color: PoolRGBA.black.alpha(0).color, location: 1)]),
                                                      center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0, endRadius: lamp))
            let rng = PoolRandom(9)
            for _ in 0..<40 {
                let x = CGFloat(Float(rng.unit())) * size.width
                let y = CGFloat(Float(rng.unit())) * size.height
                let r = CGFloat(Float(1 + rng.unit() * 2))
                let a = Float(0.04 + rng.unit() * 0.04)
                ctx.fill(PoolArt.circle(CGPoint(x: x, y: y), r), with: .color(Color.white.opacity(Double(a))))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
