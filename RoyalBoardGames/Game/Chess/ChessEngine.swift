import Foundation

// Squares are 0..63: index = rank * 8 + file, a1 = 0, h1 = 7, a8 = 56, h8 = 63.

enum ChessColor: String, CaseIterable, Codable, Hashable, Sendable {
    case WHITE, BLACK

    var opposite: ChessColor { self == .WHITE ? .BLACK : .WHITE }
    var title: String { self == .WHITE ? "White" : "Black" }

    /// Pawn direction in ranks.
    var forward: Int { self == .WHITE ? 1 : -1 }

    /// Kotlin `ordinal`.
    var ordinal: Int { self == .WHITE ? 0 : 1 }
}

enum PieceKind: CaseIterable, Hashable, Sendable {
    case PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING

    /// Kotlin `rawValue`.
    var rawValue: String {
        switch self {
        case .PAWN: "pawn"
        case .KNIGHT: "knight"
        case .BISHOP: "bishop"
        case .ROOK: "rook"
        case .QUEEN: "queen"
        case .KING: "king"
        }
    }

    /// Kotlin `ordinal` (indexes the bot's PIECE table).
    var ordinal: Int {
        switch self {
        case .PAWN: 0
        case .KNIGHT: 1
        case .BISHOP: 2
        case .ROOK: 3
        case .QUEEN: 4
        case .KING: 5
        }
    }

    var value: Int {
        switch self {
        case .PAWN: 1
        case .KNIGHT, .BISHOP: 3
        case .ROOK: 5
        case .QUEEN: 9
        case .KING: 0
        }
    }

    var letter: String {
        switch self {
        case .PAWN: ""
        case .KNIGHT: "N"
        case .BISHOP: "B"
        case .ROOK: "R"
        case .QUEEN: "Q"
        case .KING: "K"
        }
    }

    static var entries: [PieceKind] { allCases }
}

struct ChessPiece: Hashable, Sendable {
    let kind: PieceKind
    let color: ChessColor

    init(_ kind: PieceKind, _ color: ChessColor) {
        self.kind = kind
        self.color = color
    }

    init(kind: PieceKind, color: ChessColor) {
        self.init(kind, color)
    }
}

enum CastleSide: Hashable, Sendable { case KINGSIDE, QUEENSIDE }

struct ChessMove: Hashable, Sendable {
    let from: Int
    let to: Int
    var promotion: PieceKind? = nil
    var captured: PieceKind? = nil
    var isEnPassant: Bool = false
    var castle: CastleSide? = nil

    init(_ from: Int, _ to: Int, promotion: PieceKind? = nil, captured: PieceKind? = nil, isEnPassant: Bool = false, castle: CastleSide? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
        self.captured = captured
        self.isEnPassant = isEnPassant
        self.castle = castle
    }

    var isCapture: Bool { captured != nil }

    /// Long algebraic form, e.g. "e2e4" or "a7a8q" (used by autosave).
    var uci: String {
        let suffix: String
        switch promotion {
        case .QUEEN: suffix = "q"
        case .ROOK: suffix = "r"
        case .BISHOP: suffix = "b"
        case .KNIGHT: suffix = "n"
        default: suffix = ""
        }
        return ChessSquare.name(from) + ChessSquare.name(to) + suffix
    }
}

struct CastlingRights: Hashable, Sendable {
    var whiteKingside: Bool = true
    var whiteQueenside: Bool = true
    var blackKingside: Bool = true
    var blackQueenside: Bool = true

    init(_ whiteKingside: Bool = true, _ whiteQueenside: Bool = true, _ blackKingside: Bool = true, _ blackQueenside: Bool = true) {
        self.whiteKingside = whiteKingside
        self.whiteQueenside = whiteQueenside
        self.blackKingside = blackKingside
        self.blackQueenside = blackQueenside
    }

    static let NONE = CastlingRights(false, false, false, false)

    /// Kotlin `copy(...)`.
    func copy(whiteKingside: Bool? = nil, whiteQueenside: Bool? = nil, blackKingside: Bool? = nil, blackQueenside: Bool? = nil) -> CastlingRights {
        CastlingRights(whiteKingside ?? self.whiteKingside, whiteQueenside ?? self.whiteQueenside,
                       blackKingside ?? self.blackKingside, blackQueenside ?? self.blackQueenside)
    }
}

enum ChessSquare {
    private static let files: [Character] = Array("abcdefgh")

    @inline(__always) static func file(_ sq: Int) -> Int { sq & 7 }
    @inline(__always) static func rank(_ sq: Int) -> Int { sq >> 3 }

    @inline(__always)
    static func make(_ file: Int, _ rank: Int) -> Int? {
        (file >= 0 && file <= 7 && rank >= 0 && rank <= 7) ? rank * 8 + file : nil
    }

    static func name(_ sq: Int) -> String { "\(files[file(sq)])\(rank(sq) + 1)" }

    static func fileLetter(_ sq: Int) -> String { String(files[file(sq)]) }

    static func parse(_ text: String) -> Int? {
        let chars = Array(text)
        if chars.count != 2 { return nil }
        guard let f = files.firstIndex(of: chars[0]) else {
            // Kotlin checks the digit before the file; both must be valid anyway.
            return nil
        }
        guard chars[1].isNumber, let r = chars[1].wholeNumberValue else { return nil }
        return make(f, r - 1)
    }

    @inline(__always) static func isLight(_ sq: Int) -> Bool { (file(sq) + rank(sq)) % 2 == 1 }
}

/// A complete chess position with legal move generation. Immutable: `applying` returns a copy.
struct ChessPosition: Hashable, Sendable {
    let board: [ChessPiece?]
    let sideToMove: ChessColor
    let castling: CastlingRights
    let enPassant: Int?
    let halfmoveClock: Int
    let fullmoveNumber: Int

    init(_ board: [ChessPiece?], _ sideToMove: ChessColor, _ castling: CastlingRights, _ enPassant: Int?, _ halfmoveClock: Int, _ fullmoveNumber: Int) {
        self.board = board
        self.sideToMove = sideToMove
        self.castling = castling
        self.enPassant = enPassant
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
    }

    static let START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let start: ChessPosition = fromFen(START_FEN)!

    private static let knightJumps: [(Int, Int)] = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let kingSteps: [(Int, Int)] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    private static let diagonals: [(Int, Int)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let straights: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let queenDirs: [(Int, Int)] = diagonals + straights
    private static let promotionKinds: [PieceKind] = [.QUEEN, .ROOK, .BISHOP, .KNIGHT]

    // MARK: FEN

    static func fromFen(_ fen: String) -> ChessPosition? {
        let parts = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if parts.count < 4 { return nil }
        var board = [ChessPiece?](repeating: nil, count: 64)
        let ranks = parts[0].split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if ranks.count != 8 { return nil }
        for (i, row) in ranks.enumerated() {
            let rank = 7 - i
            var file = 0
            for ch in row {
                if ch.isNumber, let digit = ch.wholeNumberValue {
                    file += digit
                    continue
                }
                if file >= 8 { return nil }
                let color: ChessColor = ch.isUppercase ? .WHITE : .BLACK
                let kind: PieceKind
                switch ch.lowercased() {
                case "p": kind = .PAWN
                case "n": kind = .KNIGHT
                case "b": kind = .BISHOP
                case "r": kind = .ROOK
                case "q": kind = .QUEEN
                case "k": kind = .KING
                default: return nil
                }
                board[rank * 8 + file] = ChessPiece(kind, color)
                file += 1
            }
            if file != 8 { return nil }
        }
        let side: ChessColor = parts[1] == "b" ? .BLACK : .WHITE
        var rights = CastlingRights.NONE
        for ch in parts[2] {
            switch ch {
            case "K": rights.whiteKingside = true
            case "Q": rights.whiteQueenside = true
            case "k": rights.blackKingside = true
            case "q": rights.blackQueenside = true
            default: break
            }
        }
        let ep = parts[3] == "-" ? nil : ChessSquare.parse(parts[3])
        let half = parts.count > 4 ? (Int32(parts[4]).map { Int($0) } ?? 0) : 0
        let full = parts.count > 5 ? (Int32(parts[5]).map { Int($0) } ?? 1) : 1
        return ChessPosition(board, side, rights, ep, half, full)
    }

    private static func letterOf(_ piece: ChessPiece) -> String {
        let letter = piece.kind == .PAWN ? "p" : piece.kind.letter.lowercased()
        return piece.color == .WHITE ? letter.uppercased() : letter
    }

    var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { row += "\(empty)"; empty = 0 }
                    row += Self.letterOf(piece)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += "\(empty)" }
            rows.append(row)
        }
        var rights = ""
        if castling.whiteKingside { rights += "K" }
        if castling.whiteQueenside { rights += "Q" }
        if castling.blackKingside { rights += "k" }
        if castling.blackQueenside { rights += "q" }
        return [
            rows.joined(separator: "/"),
            sideToMove == .WHITE ? "w" : "b",
            rights.isEmpty ? "-" : rights,
            enPassant.map(ChessSquare.name) ?? "-",
            "\(halfmoveClock)",
            "\(fullmoveNumber)",
        ].joined(separator: " ")
    }

    // MARK: Queries

    func kingSquare(_ color: ChessColor) -> Int? { Self.kingSquare(board, color) }

    private static func kingSquare(_ board: [ChessPiece?], _ color: ChessColor) -> Int? {
        for i in 0..<64 {
            if let p = board[i], p.kind == .KING, p.color == color { return i }
        }
        return nil
    }

    func isInCheck(_ color: ChessColor) -> Bool {
        guard let king = kingSquare(color) else { return false }
        return isAttacked(king, color.opposite)
    }

    /// Whether `color` attacks `square`.
    func isAttacked(_ square: Int, _ color: ChessColor) -> Bool { Self.isAttacked(board, square, color) }

    private static func isAttacked(_ board: [ChessPiece?], _ square: Int, _ color: ChessColor) -> Bool {
        let f = ChessSquare.file(square)
        let r = ChessSquare.rank(square)
        // Pawns attack diagonally forward, so look one rank "behind" the square.
        for df in [-1, 1] {
            if let s = ChessSquare.make(f + df, r - color.forward), let p = board[s], p.kind == .PAWN, p.color == color { return true }
        }
        for (df, dr) in knightJumps {
            guard let s = ChessSquare.make(f + df, r + dr) else { continue }
            if let p = board[s], p.kind == .KNIGHT, p.color == color { return true }
        }
        for (df, dr) in kingSteps {
            guard let s = ChessSquare.make(f + df, r + dr) else { continue }
            if let p = board[s], p.kind == .KING, p.color == color { return true }
        }
        // Diagonals: bishops and queens; straights: rooks and queens.
        for pass in 0..<2 {
            let dirs = pass == 0 ? diagonals : straights
            let slider: PieceKind = pass == 0 ? .BISHOP : .ROOK
            for (df, dr) in dirs {
                var nf = f + df
                var nr = r + dr
                while let s = ChessSquare.make(nf, nr) {
                    if let piece = board[s] {
                        if piece.color == color && (piece.kind == slider || piece.kind == .QUEEN) { return true }
                        break
                    }
                    nf += df
                    nr += dr
                }
            }
        }
        return false
    }

    // MARK: Move generation

    func legalMoves() -> [ChessMove] { legal(pseudoLegalMoves(nil)) }

    func legalMoves(_ from: Int) -> [ChessMove] { legal(pseudoLegalMoves(from)) }

    func isLegal(_ move: ChessMove) -> Bool {
        legalMoves(move.from).contains { $0.to == move.to && $0.promotion == move.promotion }
    }

    /// Kotlin `pseudoLegalMoves(only).filter { !applying(it).isInCheck(sideToMove) }`, tested on one scratch board.
    private func legal(_ pseudo: [ChessMove]) -> [ChessMove] {
        var scratch = board
        var out = [ChessMove]()
        out.reserveCapacity(pseudo.count)
        for move in pseudo where !leavesInCheck(&scratch, move) {
            out.append(move)
        }
        return out
    }

    /// Same answer as `applying(move).isInCheck(sideToMove)`: makes the move on `b`, tests, then restores `b`.
    private func leavesInCheck(_ b: inout [ChessPiece?], _ move: ChessMove) -> Bool {
        guard let piece = b[move.from] else { return isInCheck(sideToMove) }
        let side = piece.color
        let fromOld = b[move.from]
        b[move.from] = nil
        var epSquare = -1
        var epOld: ChessPiece? = nil
        if move.isEnPassant {
            epSquare = move.to - 8 * side.forward
            epOld = b[epSquare]
            b[epSquare] = nil
        }
        let toOld = b[move.to]
        b[move.to] = move.promotion.map { ChessPiece($0, side) } ?? piece
        var rookFrom = -1
        var rookTo = -1
        var rookFromOld: ChessPiece? = nil
        var rookToOld: ChessPiece? = nil
        if let castle = move.castle {
            let home = side == .WHITE ? 4 : 60
            if castle == .KINGSIDE { rookFrom = home + 3; rookTo = home + 1 } else { rookFrom = home - 4; rookTo = home - 1 }
            rookToOld = b[rookTo]
            b[rookTo] = b[rookFrom]
            rookFromOld = b[rookFrom]
            b[rookFrom] = nil
        }
        var inCheck = false
        if let king = Self.kingSquare(b, sideToMove) { inCheck = Self.isAttacked(b, king, sideToMove.opposite) }
        // Undo in reverse order.
        if rookFrom >= 0 {
            b[rookFrom] = rookFromOld
            b[rookTo] = rookToOld
        }
        b[move.to] = toOld
        if epSquare >= 0 { b[epSquare] = epOld }
        b[move.from] = fromOld
        return inCheck
    }

    private func pseudoLegalMoves(_ only: Int?) -> [ChessMove] {
        var moves = [ChessMove]()
        moves.reserveCapacity(48)
        let side = sideToMove
        for from in 0..<64 {
            if let only, from != only { continue }
            guard let piece = board[from] else { continue }
            if piece.color != side { continue }
            let f = ChessSquare.file(from)
            let r = ChessSquare.rank(from)
            switch piece.kind {
            case .PAWN: addPawnMoves(from, f, r, side, &moves)
            case .KNIGHT: for (df, dr) in Self.knightJumps { addStep(from, f + df, r + dr, side, &moves) }
            case .KING:
                for (df, dr) in Self.kingSteps { addStep(from, f + df, r + dr, side, &moves) }
                addCastling(from, side, &moves)
            case .BISHOP: addSlides(from, f, r, Self.diagonals, side, &moves)
            case .ROOK: addSlides(from, f, r, Self.straights, side, &moves)
            case .QUEEN: addSlides(from, f, r, Self.queenDirs, side, &moves)
            }
        }
        return moves
    }

    private func addStep(_ from: Int, _ file: Int, _ rank: Int, _ side: ChessColor, _ moves: inout [ChessMove]) {
        guard let to = ChessSquare.make(file, rank) else { return }
        if let target = board[to] {
            if target.color != side { moves.append(ChessMove(from, to, captured: target.kind)) }
        } else {
            moves.append(ChessMove(from, to))
        }
    }

    private func addSlides(_ from: Int, _ file: Int, _ rank: Int, _ dirs: [(Int, Int)], _ side: ChessColor, _ moves: inout [ChessMove]) {
        for (df, dr) in dirs {
            var nf = file + df
            var nr = rank + dr
            while let to = ChessSquare.make(nf, nr) {
                if let target = board[to] {
                    if target.color != side { moves.append(ChessMove(from, to, captured: target.kind)) }
                    break
                }
                moves.append(ChessMove(from, to))
                nf += df
                nr += dr
            }
        }
    }

    private func addPawnMoves(_ from: Int, _ file: Int, _ rank: Int, _ side: ChessColor, _ moves: inout [ChessMove]) {
        let dir = side.forward
        let startRank = side == .WHITE ? 1 : 6
        let lastRank = side == .WHITE ? 7 : 0

        func add(_ to: Int, _ captured: PieceKind? = nil, _ enPassant: Bool = false, _ moves: inout [ChessMove]) {
            if ChessSquare.rank(to) == lastRank {
                for kind in Self.promotionKinds {
                    moves.append(ChessMove(from, to, promotion: kind, captured: captured))
                }
            } else {
                moves.append(ChessMove(from, to, captured: captured, isEnPassant: enPassant))
            }
        }

        if let one = ChessSquare.make(file, rank + dir), board[one] == nil {
            add(one, nil, false, &moves)
            if rank == startRank, let two = ChessSquare.make(file, rank + 2 * dir), board[two] == nil {
                moves.append(ChessMove(from, two))
            }
        }
        for df in [-1, 1] {
            guard let to = ChessSquare.make(file + df, rank + dir) else { continue }
            if let target = board[to], target.color != side {
                add(to, target.kind, false, &moves)
            } else if to == enPassant {
                add(to, .PAWN, true, &moves)
            }
        }
    }

    private func addCastling(_ from: Int, _ side: ChessColor, _ moves: inout [ChessMove]) {
        let home = side == .WHITE ? 4 : 60
        if from != home || isAttacked(home, side.opposite) { return }
        let rook = ChessPiece(.ROOK, side)
        let kingside = side == .WHITE ? castling.whiteKingside : castling.blackKingside
        let queenside = side == .WHITE ? castling.whiteQueenside : castling.blackQueenside
        if kingside && board[home + 3] == rook && board[home + 1] == nil && board[home + 2] == nil &&
            !isAttacked(home + 1, side.opposite) && !isAttacked(home + 2, side.opposite) {
            moves.append(ChessMove(home, home + 2, castle: .KINGSIDE))
        }
        if queenside && board[home - 4] == rook && board[home - 1] == nil && board[home - 2] == nil && board[home - 3] == nil &&
            !isAttacked(home - 1, side.opposite) && !isAttacked(home - 2, side.opposite) {
            moves.append(ChessMove(home, home - 2, castle: .QUEENSIDE))
        }
    }

    // MARK: Making moves

    func applying(_ move: ChessMove) -> ChessPosition {
        guard let piece = board[move.from] else { return self }
        let side = piece.color
        var next = board

        next[move.from] = nil
        if move.isEnPassant { next[move.to - 8 * side.forward] = nil }
        next[move.to] = move.promotion.map { ChessPiece($0, side) } ?? piece

        if let castle = move.castle {
            let home = side == .WHITE ? 4 : 60
            let (rookFrom, rookTo) = castle == .KINGSIDE ? (home + 3, home + 1) : (home - 4, home - 1)
            next[rookTo] = next[rookFrom]
            next[rookFrom] = nil
        }

        // Castling rights disappear when the king or a rook moves, or a rook is captured on its corner.
        var rights = castling
        func strip(_ square: Int) {
            switch square {
            case 4: rights.whiteKingside = false; rights.whiteQueenside = false
            case 60: rights.blackKingside = false; rights.blackQueenside = false
            case 0: rights.whiteQueenside = false
            case 7: rights.whiteKingside = false
            case 56: rights.blackQueenside = false
            case 63: rights.blackKingside = false
            default: break
            }
        }
        strip(move.from)
        strip(move.to)

        let ep: Int? = (piece.kind == .PAWN && abs(move.to - move.from) == 16) ? move.from + 8 * side.forward : nil
        let half = (piece.kind == .PAWN || board[move.to] != nil || move.isEnPassant) ? 0 : halfmoveClock + 1
        let full = side == .BLACK ? fullmoveNumber + 1 : fullmoveNumber
        return ChessPosition(next, side.opposite, rights, ep, half, full)
    }

    // MARK: Draw helpers

    /// Identity for repetition: pieces, side to move, castling rights and a *usable* en-passant square.
    var repetitionKey: String {
        var key = ""
        key.reserveCapacity(90)
        for piece in board { key += piece.map(Self.letterOf) ?? "." }
        key += sideToMove == .WHITE ? "w" : "b"
        key += "\(castling.whiteKingside)\(castling.whiteQueenside)\(castling.blackKingside)\(castling.blackQueenside)"
        if let ep = enPassant, legalMoves().contains(where: { $0.isEnPassant && $0.to == ep }) { key += ChessSquare.name(ep) }
        return key
    }

    /// Neither side can possibly deliver mate.
    var hasInsufficientMaterial: Bool {
        var minors = 0
        var allBishops = true
        var bishopOnLight = false
        var bishopOnDark = false
        for square in 0..<64 {
            guard let piece = board[square], piece.kind != .KING else { continue }
            switch piece.kind {
            case .PAWN, .ROOK, .QUEEN: return false
            default:
                minors += 1
                if piece.kind == .BISHOP {
                    if ChessSquare.isLight(square) { bishopOnLight = true } else { bishopOnDark = true }
                } else {
                    allBishops = false
                }
            }
        }
        if minors <= 1 { return true }
        // Only bishops, all on the same square colour.
        if allBishops { return bishopOnLight != bishopOnDark }
        return false
    }

    /// Whether `color` has enough material to ever checkmate (used for timeouts).
    func canMate(_ color: ChessColor) -> Bool {
        var knights = 0
        var bishopOnLight = false
        var bishopOnDark = false
        for square in 0..<64 {
            guard let piece = board[square], piece.color == color, piece.kind != .KING else { continue }
            switch piece.kind {
            case .PAWN, .ROOK, .QUEEN: return true
            case .KNIGHT: knights += 1
            case .BISHOP: if ChessSquare.isLight(square) { bishopOnLight = true } else { bishopOnDark = true }
            case .KING: break
            }
        }
        let bishopColours = (bishopOnLight ? 1 : 0) + (bishopOnDark ? 1 : 0)
        return knights >= 2 || bishopColours == 2 || (knights >= 1 && bishopColours > 0)
    }

    // MARK: Notation

    /// Standard Algebraic Notation for a legal move in this position.
    func san(_ move: ChessMove) -> String {
        guard let piece = board[move.from] else { return "?" }
        var text: String
        if let castle = move.castle {
            text = castle == .KINGSIDE ? "O-O" : "O-O-O"
        } else if piece.kind == .PAWN {
            text = move.isCapture ? "\(ChessSquare.fileLetter(move.from))x" : ""
            text += ChessSquare.name(move.to)
            if let promotion = move.promotion { text += "=\(promotion.letter)" }
        } else {
            text = piece.kind.letter
            let rivals = legalMoves().filter { $0.to == move.to && $0.from != move.from && board[$0.from]?.kind == piece.kind }
            if !rivals.isEmpty {
                let sameFile = rivals.contains { ChessSquare.file($0.from) == ChessSquare.file(move.from) }
                let sameRank = rivals.contains { ChessSquare.rank($0.from) == ChessSquare.rank(move.from) }
                let square = ChessSquare.name(move.from)
                text += !sameFile ? String(square.prefix(1)) : (!sameRank ? String(square.suffix(1)) : square)
            }
            if move.isCapture { text += "x" }
            text += ChessSquare.name(move.to)
        }
        let after = applying(move)
        if after.isInCheck(after.sideToMove) {
            text += after.legalMoves().isEmpty ? "#" : "+"
        }
        return text
    }

    /// Counts leaf nodes to `depth` (standard move-generator test).
    func perft(_ depth: Int) -> Int {
        if depth <= 0 { return 1 }
        let moves = legalMoves()
        if depth == 1 { return moves.count }
        var total = 0
        for move in moves { total += applying(move).perft(depth - 1) }
        return total
    }
}

// MARK: - Match

enum ChessResult: Hashable, Sendable {
    case Checkmate(by: ChessColor)
    case Resignation(by: ChessColor)
    case Timeout(by: ChessColor)
    case Stalemate
    case InsufficientMaterial
    case FivefoldRepetition
    case SeventyFiveMoves
    case ThreefoldRepetition
    case FiftyMoves
    case Agreement
    case TimeoutVsInsufficientMaterial

    var winner: ChessColor? {
        switch self {
        case .Checkmate(let by), .Resignation(let by), .Timeout(let by): by
        default: nil
        }
    }

    var title: String {
        switch self {
        case .Checkmate: "Checkmate!"
        case .Resignation: "Resignation"
        case .Timeout: "Time's up!"
        default: "It's a draw"
        }
    }

    var reason: String {
        switch self {
        case .Checkmate: "Checkmate — the king has no escape"
        case .Resignation(let by): "\(by.opposite.title) resigned"
        case .Timeout(let by): "\(by.opposite.title) ran out of time"
        case .Stalemate: "Stalemate — no legal moves, but no check"
        case .InsufficientMaterial: "Neither side can checkmate"
        case .FivefoldRepetition: "Same position five times"
        case .SeventyFiveMoves: "75 moves without a capture or pawn move"
        case .ThreefoldRepetition: "Threefold repetition claimed"
        case .FiftyMoves: "50-move rule claimed"
        case .Agreement: "Draw agreed"
        case .TimeoutVsInsufficientMaterial: "Time ran out, but the opponent can't checkmate"
        }
    }
}

/// A game in progress: position history, notation, draw claims and results. A value type: copy to branch.
struct ChessMatch: Sendable {
    private(set) var position: ChessPosition
    private var _moves: [ChessMove] = []
    private var _san: [String] = []
    var moves: [ChessMove] { _moves }
    var sanMoves: [String] { _san }
    private(set) var result: ChessResult? = nil
    private var repetitions: [String: Int] = [:]

    init(_ start: ChessPosition = ChessPosition.start) {
        position = start
        repetitions[position.repetitionKey] = 1
        evaluateAutomaticEnd()
    }

    /// Kotlin `copy()`.
    func copy() -> ChessMatch { self }

    var isOver: Bool { result != nil }
    var lastMove: ChessMove? { _moves.last }
    var canClaimThreefold: Bool { !isOver && (repetitions[position.repetitionKey] ?? 0) >= 3 }
    var canClaimFiftyMoves: Bool { !isOver && position.halfmoveClock >= 100 }

    /// Pieces taken by `by`.
    func captured(_ by: ChessColor) -> [PieceKind] {
        var taken: [PieceKind] = []
        var side = ChessColor.WHITE
        for move in _moves {
            if side == by, let c = move.captured { taken.append(c) }
            side = side.opposite
        }
        return taken.chessStableSorted(descendingBy: { $0.value })
    }

    /// Material balance from White's point of view.
    var materialBalance: Int {
        var sum = 0
        for case let p? in position.board { sum += p.color == .WHITE ? p.kind.value : -p.kind.value }
        return sum
    }

    /// Plays a move if it's legal in the current position; returns the move as played.
    @discardableResult
    mutating func play(_ from: Int, _ to: Int, _ promotion: PieceKind? = nil) -> ChessMove? {
        if isOver { return nil }
        // Promotions must name the piece; everything else must not.
        guard let move = position.legalMoves(from).first(where: { $0.to == to && $0.promotion == promotion }) else { return nil }
        _san.append(position.san(move))
        _moves.append(move)
        position = position.applying(move)
        let key = position.repetitionKey
        repetitions[key] = (repetitions[key] ?? 0) + 1
        evaluateAutomaticEnd()
        return move
    }

    /// Whether a pawn move from → to needs a promotion choice.
    func needsPromotion(_ from: Int, _ to: Int) -> Bool {
        position.legalMoves(from).contains { $0.to == to && $0.promotion != nil }
    }

    mutating func resign(_ color: ChessColor) {
        if isOver { return }
        result = .Resignation(by: color.opposite)
    }

    mutating func agreeDraw() {
        if isOver { return }
        result = .Agreement
    }

    mutating func claimDraw() {
        if canClaimThreefold {
            result = .ThreefoldRepetition
        } else if canClaimFiftyMoves {
            result = .FiftyMoves
        }
    }

    mutating func flag(_ color: ChessColor) {
        if isOver { return }
        result = position.canMate(color.opposite) ? .Timeout(by: color.opposite) : .TimeoutVsInsufficientMaterial
    }

    private mutating func evaluateAutomaticEnd() {
        let side = position.sideToMove
        if position.legalMoves().isEmpty {
            result = position.isInCheck(side) ? .Checkmate(by: side.opposite) : .Stalemate
        } else if position.hasInsufficientMaterial {
            result = .InsufficientMaterial
        } else if (repetitions[position.repetitionKey] ?? 0) >= 5 {
            result = .FivefoldRepetition
        } else if position.halfmoveClock >= 150 {
            result = .SeventyFiveMoves
        }
    }
}

extension Array {
    /// Kotlin `sortedByDescending` — stable: equal keys keep their order.
    func chessStableSorted(descendingBy key: (Element) -> Int) -> [Element] {
        if count < 2 { return self }
        var keyed: [(Int, Element)] = map { (key($0), $0) }
        // Insertion sort with a strict comparison keeps equal elements in order.
        for i in 1..<keyed.count {
            let current = keyed[i]
            var j = i - 1
            while j >= 0 && keyed[j].0 < current.0 {
                keyed[j + 1] = keyed[j]
                j -= 1
            }
            keyed[j + 1] = current
        }
        return keyed.map { $0.1 }
    }
}
