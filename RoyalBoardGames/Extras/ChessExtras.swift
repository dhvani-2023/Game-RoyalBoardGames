import SwiftUI
import UIKit
import GameKit

// MARK: - Undo

/// Taking moves back against the computer: the person's last move plus the computer's reply to it, if made.
enum ChessUndo {
    /// How many plies come off so that it's the person's move again before their last move; 0 when there's
    /// nothing of theirs to take back (or the game is over).
    static func plies(_ match: ChessMatch, _ human: ChessColor) -> Int {
        if match.isOver { return 0 }
        let k = match.position.sideToMove == human ? 2 : 1
        return match.moves.count >= k ? k : 0
    }

    /// The same game with its last [plies] moves taken back, replayed from the start so repetition counts and
    /// notation stay exact.
    static func rewound(_ match: ChessMatch, _ plies: Int) -> ChessMatch {
        var replay = ChessMatch()
        for move in match.moves.prefix(max(0, match.moves.count - plies)) {
            if replay.play(move.from, move.to, move.promotion) == nil { break }
        }
        return replay
    }
}

// MARK: - PGN

/// The game in Portable Game Notation: the seven-tag roster and the SAN moves, wrapped at 80 columns.
enum ChessPGN {
    static func result(_ r: ChessResult?) -> String {
        guard let r else { return "*" }
        switch r.winner {
        case .WHITE?: return "1-0"
        case .BLACK?: return "0-1"
        case nil: return "1/2-1/2"
        }
    }

    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: d)
    }

    private static func tag(_ name: String, _ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "[\(name) \"\(escaped)\"]"
    }

    /// Just the move text, e.g. `1. e4 e5 2. Nf3 *`.
    static func movetext(_ match: ChessMatch) -> String {
        var tokens: [String] = []
        for (i, san) in match.sanMoves.enumerated() {
            if i % 2 == 0 { tokens.append("\(i / 2 + 1).") }
            tokens.append(san)
        }
        tokens.append(result(match.result))
        var lines: [String] = []
        var line = ""
        for token in tokens {
            if line.isEmpty {
                line = token
            } else if line.count + 1 + token.count > 80 {
                lines.append(line)
                line = token
            } else {
                line += " " + token
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines.joined(separator: "\n")
    }

    static func export(_ match: ChessMatch, white: String, black: String, date: Date = Date(), event: String = "Casual game") -> String {
        let tags = [
            tag("Event", event),
            tag("Site", "Board Games: Royal Club"),
            tag("Date", self.date(date)),
            tag("Round", "-"),
            tag("White", white),
            tag("Black", black),
            tag("Result", result(match.result)),
        ]
        return tags.joined(separator: "\n") + "\n\n" + movetext(match) + "\n"
    }
}

// MARK: - Session tools

extension ChessSession {
    /// Undo is for games against the computer, once the person has a move to take back.
    var canUndo: Bool {
        guard ExtrasFeatures.chessTools, let human = humanColor else { return false }
        return passTo == nil && pendingPromotion == nil && ChessUndo.plies(match, human) > 0
    }

    /// A hint is the computer's choice at the game's level, for the person to move.
    var canHint: Bool {
        ExtrasFeatures.chessTools && config.hasBot && !match.isOver && !isBot(sideToMove) && passTo == nil
            && pendingPromotion == nil && !hintBusy
    }

    func requestHint() {
        guard canHint else { return }
        if hint != nil { hint = nil; return }
        hintBusy = true
        let snapshot = position
        let level = config.botLevel
        let ply = match.moves.count
        Task { @MainActor [weak self] in
            let move = await Task.detached(priority: .userInitiated) { ChessBot.bestMove(snapshot, level) }.value
            guard let self else { return }
            self.hintBusy = false
            guard self.match.moves.count == ply, !self.match.isOver, let move else { return }
            self.hint = move
            UiSound.play(.Chime)
            Haptics.play(.Light)
        }
    }

    var pgn: String {
        ChessPGN.export(match, white: config.white.name, black: config.black.name,
                        event: config.hasBot ? "Casual game vs computer" : "Casual game")
    }

    func copyPGN() {
        UIPasteboard.general.string = pgn
        UiSound.play(.Chime)
        Haptics.play(.Success)
        showNotice("PGN copied to the clipboard")
    }
}

// MARK: - Board hint

/// The hinted move: both squares ringed and an arrow between them.
struct ExtrasChessHintOverlay: View {
    let move: ChessMove
    let flipped: Bool
    let square: CGFloat

    @State private var shown = false

    var body: some View {
        let colour = Royal.Emerald
        Canvas { ctx, _ in
            let a = ChessBoard.center(move.from, flipped, square)
            let b = ChessBoard.center(move.to, flipped, square)
            for c in [a, b] {
                let r = CGRect(x: c.x - square / 2 + 2, y: c.y - square / 2 + 2, width: square - 4, height: square - 4)
                ctx.fill(Path(roundedRect: r, cornerRadius: square * 0.12), with: .color(colour.opacity(0.22)))
                ctx.stroke(Path(roundedRect: r, cornerRadius: square * 0.12), with: .color(colour.opacity(0.95)), lineWidth: max(2, square * 0.06))
            }
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len = max(0.001, hypot(dx, dy))
            let ux = dx / len
            let uy = dy / len
            let head = square * 0.34
            let tip = CGPoint(x: b.x - ux * square * 0.18, y: b.y - uy * square * 0.18)
            let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
            var shaft = Path()
            shaft.move(to: CGPoint(x: a.x + ux * square * 0.2, y: a.y + uy * square * 0.2))
            shaft.addLine(to: base)
            ctx.stroke(shaft, with: .color(colour.opacity(0.85)), style: StrokeStyle(lineWidth: square * 0.14, lineCap: .round))
            var arrow = Path()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: base.x - uy * head * 0.6, y: base.y + ux * head * 0.6))
            arrow.addLine(to: CGPoint(x: base.x + uy * head * 0.6, y: base.y - ux * head * 0.6))
            arrow.closeSubpath()
            ctx.fill(arrow, with: .color(colour.opacity(0.9)))
        }
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.96)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.compose(dampingRatio: 0.8, stiffness: 400)) { shown = true } }
        .accessibilityHidden(true)
    }
}

// MARK: - Move list panel

/// A scrollable list of the moves in SAN, two per row, following the latest move; Copy PGN in its header.
struct ExtrasChessMoveList: View {
    let session: ChessSession
    let accent: Color

    var body: some View {
        let pairs = session.movePairs
        let plies = session.match.sanMoves.count
        let shape = RoundedCornerShape(18)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Icon(Icons.Rounded.FormatListNumbered, tint: Royal.Gold, size: 18)
                Text("Moves", style: bodyStyle(14, .ExtraBold, Royal.Ivory))
                Text("\(pairs.count)", style: bodyStyle(12, .Bold, Royal.Smoke))
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Icon(Icons.Rounded.Description, tint: Royal.Gold, size: 14)
                    Text("Copy PGN", style: bodyStyle(11, .ExtraBold, Royal.Gold)).lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Royal.Glass))
                .overlay(Capsule().strokeBorder(Royal.Gold.opacity(0.6), lineWidth: 1))
                .fixedSize()
                .opacity(plies > 0 ? 1 : 0.45)
                .pressable(enabled: plies > 0) { session.copyPGN() }
                .accessibilityLabel("Copy the game as PGN")
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if pairs.isEmpty {
                            Text("Moves appear here", style: bodyStyle(13, .SemiBold, Royal.Smoke))
                                .padding(.vertical, 6)
                        }
                        ForEach(pairs) { pair in
                            row(pair, plies)
                                .id(pair.number)
                        }
                    }
                    .padding(.trailing, 6)
                }
                .onAppear {
                    if let last = pairs.last { proxy.scrollTo(last.number, anchor: .bottom) }
                }
                .onChange(of: session.moveCount) { _, _ in
                    if let last = session.movePairs.last {
                        withAnimation(.compose(dampingRatio: 1, stiffness: 400)) { proxy.scrollTo(last.number, anchor: .bottom) }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(Royal.panelBrush))
        .overlay(shape.strokeBorder(Royal.Stroke, lineWidth: 1))
        .clipShape(shape)
        .accessibilityElement(children: .contain)
    }

    private func row(_ pair: ChessSession.MovePair, _ plies: Int) -> some View {
        let whitePly = (pair.number - 1) * 2 + 1
        return HStack(spacing: 0) {
            Text("\(pair.number).").foregroundStyle(Royal.Smoke).frame(width: 40, alignment: .leading)
            cell(pair.white, whitePly == plies)
            cell(pair.black ?? "", whitePly + 1 == plies)
        }
        .font(.system(size: 14, weight: .semibold, design: .monospaced))
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func cell(_ text: String, _ last: Bool) -> some View {
        Text(text)
            .foregroundStyle(Royal.Ivory)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(last ? accent.copy(alpha: 0.35) : Color.clear))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Table Settings action

/// One extra button in the shared Table Settings sheet (Chess: Copy PGN).
struct QuickSettingsAction {
    let title: String
    let icon: ImageVector
    let action: () -> Void
}

enum ExtrasChessIcons {
    static let Hint = ImageVector("lightbulb.fill")
}
