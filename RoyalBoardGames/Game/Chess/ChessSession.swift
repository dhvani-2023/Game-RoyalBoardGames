import Foundation
import Observation
import GameKit

/// Drives one local chess match: selection, legal moves, animation identity, clocks, hand-offs and the bot.
@MainActor
@Observable
final class ChessSession {
    /// A piece with a stable identity so moves animate instead of popping.
    struct BoardPiece: Hashable, Identifiable {
        let id: Int
        let piece: ChessPiece
        let square: Int

        func copy(piece: ChessPiece? = nil, square: Int? = nil) -> BoardPiece {
            BoardPiece(id: id, piece: piece ?? self.piece, square: square ?? self.square)
        }
    }

    /// Kotlin `Pair<Int, Int>` of a pending promotion (from → to).
    struct SquarePair: Hashable {
        let first: Int
        let second: Int
    }

    private(set) var config: ChessConfig
    private(set) var match = ChessMatch()
    private(set) var pieces: [BoardPiece] = []
    /// Captured pieces fading out where they stood.
    private(set) var ghosts: [BoardPiece] = []
    private(set) var selected: Int? = nil
    /// square → is capture
    private(set) var targets: [Int: Bool] = [:]
    private(set) var pendingPromotion: SquarePair? = nil
    var flipped = false
    private(set) var clocks: [ChessColor: Double] = [:]
    private(set) var passTo: ChessColor? = nil
    private(set) var moveCount = 0
    private(set) var captureCount = 0
    private(set) var checkCount = 0
    private(set) var illegalCount = 0
    private(set) var resultCount = 0
    private(set) var botThinking = false
    /// Short message such as "CPU Leo declines the draw".
    private(set) var notice: String? = nil
    private(set) var noticeId = 0
    /// Bumped whenever `targets` is replaced (the legal-move dots pop in again).
    private(set) var targetsVersion = 0
    /// Extras: the computer's suggestion for the person to move, drawn on the board (see `ChessExtras.swift`).
    var hint: ChessMove? = nil
    /// Extras: a hint search is running.
    var hintBusy = false

    @ObservationIgnored private var lastTick: Int64 = ChessSession.nanoTime()
    @ObservationIgnored private var nextPieceId = 0
    /// Bumped on reset / result so stale tasks (bot, hand-off) do nothing.
    @ObservationIgnored private var turnToken = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var botTask: Task<Void, Never>? = nil
    /// iOS: while the app is inactive the clocks hold (phone calls, Control Center); they restart from now.
    @ObservationIgnored var suspended = false {
        didSet { if !suspended { lastTick = Self.nanoTime() } }
    }

    init(_ config: ChessConfig) {
        self.config = config
        reset()
    }

    nonisolated static func nanoTime() -> Int64 { Int64(bitPattern: DispatchTime.now().uptimeNanoseconds) }

    var position: ChessPosition { match.position }
    var sideToMove: ChessColor { position.sideToMove }
    var usesClock: Bool { config.clock.seconds != nil }
    var isPaused: Bool { passTo != nil || pendingPromotion != nil || match.isOver }

    func player(_ color: ChessColor) -> PartyPlayer { color == .WHITE ? config.white : config.black }
    func isBot(_ color: ChessColor) -> Bool { config.isBot(color) }

    /// The human's colour in a game against the computer (nil for two people).
    var humanColor: ChessColor? {
        if config.whiteIsBot && !config.blackIsBot { return .BLACK }
        if config.blackIsBot && !config.whiteIsBot { return .WHITE }
        return nil
    }

    var checkedKing: Int? { position.isInCheck(sideToMove) ? position.kingSquare(sideToMove) : nil }

    var statusText: String {
        if let result = match.result {
            if let winner = result.winner { return "\(result.title) \(player(winner).name) wins" }
            return result.reason
        }
        let name = player(sideToMove).name
        if position.isInCheck(sideToMove) { return "Check! \(name) must respond" }
        if isBot(sideToMove) && botThinking { return "\(name) is thinking…" }
        return "\(name) to move"
    }

    // MARK: Setup

    func reset() {
        turnToken += 1
        botTask?.cancel()
        match = ChessMatch()
        hint = nil
        rebuildPieces()
        ghosts.removeAll()
        selected = nil
        setTargets([:])
        pendingPromotion = nil
        passTo = nil
        botThinking = false
        flipped = humanColor == .BLACK
        moveCount = 0
        if let seconds = config.clock.seconds { clocks = [.WHITE: seconds, .BLACK: seconds] } else { clocks = [:] }
        lastTick = Self.nanoTime()
        maybeBotMove()
    }

    private func rebuildPieces() {
        var list: [BoardPiece] = []
        nextPieceId = 0
        for (square, piece) in position.board.enumerated() {
            guard let piece else { continue }
            list.append(BoardPiece(id: nextPieceId, piece: piece, square: square))
            nextPieceId += 1
        }
        pieces = list
    }

    /// New game with the same players; `swapColors` gives the other player White.
    func rematch(_ swapColors: Bool) {
        if swapColors {
            let c = config
            config = c.copy(white: c.black, black: c.white, whiteIsBot: c.blackIsBot, blackIsBot: c.whiteIsBot)
        }
        reset()
    }

    /// Continues an autosaved match.
    func restore(_ saved: ChessSaved) {
        config = saved.config
        reset()
        turnToken += 1
        botThinking = false
        selected = nil
        setTargets([:])
        var replay = ChessMatch()
        for text in saved.moves {
            guard let from = ChessSquare.parse(String(text.prefix(2))) else { break }
            guard let to = ChessSquare.parse(String(text.dropFirst(2).prefix(2))) else { break }
            let chars = Array(text)
            let promotion: PieceKind?
            switch chars.count > 4 ? chars[4] : nil {
            case "q": promotion = .QUEEN
            case "r": promotion = .ROOK
            case "b": promotion = .BISHOP
            case "n": promotion = .KNIGHT
            default: promotion = nil
            }
            if replay.play(from, to, promotion) == nil { break }
        }
        match = replay
        rebuildPieces()
        moveCount = replay.moves.count
        if usesClock {
            let base = config.clock.seconds ?? 0
            clocks = [.WHITE: saved.whiteClock ?? base, .BLACK: saved.blackClock ?? base]
        }
        flipped = saved.flipped
        lastTick = Self.nanoTime()
        if config.passDevice && !config.hasBot && moveCount > 0 && !match.isOver { passTo = sideToMove }
        maybeBotMove()
    }

    func save() {
        if match.isOver || moveCount == 0 {
            Prefs.remove(ChessGame.SAVE_KEY)
            return
        }
        Prefs.save(
            ChessGame.SAVE_KEY,
            ChessSaved(
                config: config,
                moves: match.moves.map(\.uci),
                whiteClock: clocks[.WHITE],
                blackClock: clocks[.BLACK],
                flipped: flipped
            )
        )
    }

    /// Stops pending work when the screen goes away (Kotlin: the composition's coroutine scope is cancelled).
    func dispose() {
        turnToken += 1
        botTask?.cancel()
        botTask = nil
    }

    // MARK: Interaction

    private var humanTurn: Bool { !isBot(sideToMove) }

    func tap(_ square: Int) {
        if match.isOver || passTo != nil || pendingPromotion != nil || !humanTurn { return }
        if let piece = position.board[square], piece.color == sideToMove {
            select(square == selected ? nil : square)
            UiSound.play(.Tap)
            return
        }
        guard let from = selected else { return }
        if targets[square] != nil {
            attemptMove(from, square)
        } else {
            illegalCount += 1
            select(nil)
        }
    }

    /// Drag-and-drop entry point. Returns whether the move was accepted.
    @discardableResult
    func drop(_ from: Int, _ to: Int) -> Bool {
        if match.isOver || passTo != nil || pendingPromotion != nil || from == to || !humanTurn { return false }
        if position.board[from]?.color != sideToMove { return false }
        select(from)
        if targets[to] == nil {
            illegalCount += 1
            return false
        }
        attemptMove(from, to)
        return true
    }

    /// Selects the side-to-move's piece on `square` (used when a drag starts).
    func pick(_ square: Int) {
        if !canDrag(square) || selected == square { return }
        select(square)
    }

    func canDrag(_ square: Int) -> Bool {
        !match.isOver && passTo == nil && pendingPromotion == nil && humanTurn && position.board[square]?.color == sideToMove
    }

    private func select(_ square: Int?) {
        selected = square
        guard let square else {
            setTargets([:])
            return
        }
        var map: [Int: Bool] = [:]
        for move in position.legalMoves(square) { map[move.to] = move.isCapture }
        setTargets(map)
    }

    /// Kotlin keys the dots' pop-in on the map itself, so an equal map doesn't replay it.
    private func setTargets(_ map: [Int: Bool]) {
        if map == targets { return }
        targets = map
        targetsVersion += 1
    }

    private func attemptMove(_ from: Int, _ to: Int) {
        if match.needsPromotion(from, to) {
            pendingPromotion = SquarePair(first: from, second: to)
        } else {
            commit(from, to, nil)
        }
    }

    func promote(_ kind: PieceKind) {
        guard let pending = pendingPromotion else { return }
        pendingPromotion = nil
        commit(pending.first, pending.second, kind)
    }

    func cancelPromotion() {
        pendingPromotion = nil
        select(nil)
    }

    private func commit(_ from: Int, _ to: Int, _ promotion: PieceKind?) {
        let mover = sideToMove
        guard let move = match.play(from, to, promotion) else {
            illegalCount += 1
            select(nil)
            return
        }
        applyToPieces(move, mover)
        hint = nil
        selected = nil
        setTargets([:])
        moveCount += 1
        if let left = clocks[mover] { clocks[mover] = left + config.clock.increment }
        lastTick = Self.nanoTime()

        if match.isOver {
            resultCount += 1
            turnToken += 1
            UiSound.play(match.result?.winner == nil ? .Draw : .Win)
            save()
            return
        }
        if position.isInCheck(sideToMove) {
            checkCount += 1
            UiSound.play(.Check)
        } else {
            UiSound.play(move.isCapture ? .Capture : .Move)
        }
        if move.isCapture { captureCount += 1 }
        save()

        let token = turnToken
        if config.autoRotate && !config.hasBot {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, token == self.turnToken else { return }
                self.flipped = self.sideToMove == .BLACK
            }
        }
        if config.passDevice && !config.hasBot {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard let self, token == self.turnToken, !self.match.isOver else { return }
                self.passTo = self.sideToMove
            }
        }
        maybeBotMove()
    }

    private func applyToPieces(_ move: ChessMove, _ mover: ChessColor) {
        let captureSquare = move.isEnPassant ? move.to - 8 * mover.forward : move.to
        var list = pieces
        if move.isCapture {
            let taken = list.filter { $0.square == captureSquare }
            list.removeAll { $0.square == captureSquare }
            ghosts.append(contentsOf: taken)
        }
        if let index = list.firstIndex(where: { $0.square == move.from }) {
            let p = list[index]
            list[index] = p.copy(piece: move.promotion.map { ChessPiece($0, mover) } ?? p.piece, square: move.to)
        }
        if let castle = move.castle {
            let home = mover == .WHITE ? 4 : 60
            let (rookFrom, rookTo) = castle == .KINGSIDE ? (home + 3, home + 1) : (home - 4, home - 1)
            if let r = list.firstIndex(where: { $0.square == rookFrom }) { list[r] = list[r].copy(square: rookTo) }
        }
        pieces = list
    }

    /// Extras: takes back the person's last move against the computer, and the computer's reply if it made one
    /// (which moves come off is decided by `ChessUndo.plies`).
    func undo() {
        guard let human = humanColor, passTo == nil, pendingPromotion == nil else { return }
        let plies = ChessUndo.plies(match, human)
        if plies == 0 { return }
        turnToken += 1
        botTask?.cancel()
        botTask = nil
        botThinking = false
        match = ChessUndo.rewound(match, plies)
        hint = nil
        rebuildPieces()
        ghosts.removeAll()
        selected = nil
        setTargets([:])
        moveCount = match.moves.count
        lastTick = Self.nanoTime()
        UiSound.play(.Back)
        save()
    }

    func clearGhost(_ id: Int) {
        ghosts.removeAll { $0.id == id }
    }

    func ready() {
        lastTick = Self.nanoTime()
        passTo = nil
    }

    // MARK: Computer

    /// Called once the screen is on display (tasks must not start while the view is being built).
    func start() {
        if started { return }
        started = true
        maybeBotMove()
    }

    private func maybeBotMove() {
        if !started || match.isOver || !isBot(sideToMove) { return }
        turnToken += 1
        let token = turnToken
        let snapshot = position
        let level = config.botLevel
        botThinking = true
        botTask?.cancel()
        botTask = Task { @MainActor [weak self] in
            let t0 = Self.nanoTime()
            // The search runs off the main thread; cancelling this task stops it early.
            let worker = Task.detached(priority: .userInitiated) { ChessBot.bestMove(snapshot, level) }
            let move = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            let elapsed = (Self.nanoTime() - t0) / 1_000_000
            try? await Task.sleep(for: .milliseconds(max(0, 520 - elapsed)))
            guard let self, !Task.isCancelled, token == self.turnToken, !self.match.isOver else { return }
            guard let move else {
                self.botThinking = false
                return
            }
            // Lift the piece first so the move reads clearly.
            self.selected = move.from
            self.setTargets([move.to: move.isCapture])
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, token == self.turnToken else { return }
            self.botThinking = false
            self.commit(move.from, move.to, move.promotion)
        }
    }

    /// Whether the computer accepts a draw offer: only when it stands clearly worse.
    func botAcceptsDraw() -> Bool {
        let bot: ChessColor
        if config.whiteIsBot {
            bot = .WHITE
        } else if config.blackIsBot {
            bot = .BLACK
        } else {
            return true
        }
        return ChessBot.evaluate(position, bot) <= -120
    }

    func showNotice(_ text: String) {
        notice = text
        noticeId += 1
    }

    func clearNotice(_ id: Int) {
        if noticeId == id { notice = nil }
    }

    // MARK: Results

    func resign(_ color: ChessColor) {
        match.resign(color)
        finish()
    }

    func agreeDraw() {
        match.agreeDraw()
        finish()
    }

    func claimDraw() {
        match.claimDraw()
        finish()
    }

    private func finish() {
        turnToken += 1
        botTask?.cancel()
        botThinking = false
        passTo = nil
        pendingPromotion = nil
        selected = nil
        setTargets([:])
        resultCount += 1
        UiSound.play(match.result?.winner == nil ? .Draw : .Win)
        save()
    }

    // MARK: Clock

    /// Called frequently by the view; subtracts elapsed time from the side to move.
    func tick(_ now: Int64 = ChessSession.nanoTime()) {
        let elapsed = Double(now - lastTick) / 1e9
        lastTick = now
        if suspended || !usesClock || isPaused || moveCount == 0 { return }
        guard let remaining = clocks[sideToMove] else { return }
        let left = remaining - elapsed
        if left <= 0 {
            clocks[sideToMove] = 0.0
            match.flag(sideToMove)
            finish()
        } else {
            clocks[sideToMove] = left
        }
    }

    // MARK: Notation

    struct MovePair: Hashable, Identifiable {
        let number: Int
        let white: String
        let black: String?
        var id: Int { number }
    }

    /// Move pairs for display, e.g. 1. e4 e5.
    var movePairs: [MovePair] {
        let san = match.sanMoves
        return stride(from: 0, to: san.count, by: 2).map { i in
            MovePair(number: i / 2 + 1, white: san[i], black: i + 1 < san.count ? san[i + 1] : nil)
        }
    }

    static func format(_ seconds: Double) -> String {
        if seconds < 10 { return String(format: "0:%04.1f", max(0.0, seconds)) }
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
