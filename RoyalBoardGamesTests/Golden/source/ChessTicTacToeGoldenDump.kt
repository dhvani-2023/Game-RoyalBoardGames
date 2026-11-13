// JVM golden dump for the iOS port of Chess and Tic-Tac-Toe (Board Games: Royal Club).
// Compiled together with unmodified copies of game/chess/ChessEngine.kt, ChessBot.kt and
// game/tictactoe/TicTacToeEngine.kt (kotlinx.serialization annotations stripped) and a BotLevel stub.
// Run: kotlinc src -include-runtime -d golden.jar && java -cp golden.jar ChessTicTacToeGoldenKt <outDir>
import com.ngstudio.royalboardgames.game.chess.ChessBot
import com.ngstudio.royalboardgames.game.chess.ChessColor
import com.ngstudio.royalboardgames.game.chess.ChessMatch
import com.ngstudio.royalboardgames.game.chess.ChessPosition
import com.ngstudio.royalboardgames.game.common.BotLevel
import com.ngstudio.royalboardgames.game.tictactoe.TTTMark
import com.ngstudio.royalboardgames.game.tictactoe.TicTacToeBoard
import com.ngstudio.royalboardgames.game.tictactoe.TicTacToeBot
import java.io.File
import kotlin.random.Random

private fun q(s: String?) = if (s == null) "null" else "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
private fun arr(items: List<String>) = items.joinToString(",", "[", "]")

private val FENS = listOf(
    ChessPosition.START_FEN,
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
    "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1",
    "4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1",
    "8/8/4k3/8/2p5/8/B2K4/8 w - - 0 1",
    "r1b1k2r/ppppnppp/2n2q2/2b5/3NP3/2P1B3/PP3PPP/RN1QKB1R w KQkq - 1 7",
)

private data class GameSpec(val white: Int, val black: Int, val seed: Int, val maxPlies: Int, val fen: String)

private fun chessGolden(): String {
    val games = listOf(
        GameSpec(0, 0, 1, 80, ChessPosition.START_FEN),
        GameSpec(0, 0, 2, 80, ChessPosition.START_FEN),
        GameSpec(0, 0, 3, 80, ChessPosition.START_FEN),
        GameSpec(1, 1, 1, 40, ChessPosition.START_FEN),
        GameSpec(1, 1, 2, 40, ChessPosition.START_FEN),
        GameSpec(2, 2, 1, 14, ChessPosition.START_FEN),
        GameSpec(2, 0, 5, 160, ChessPosition.START_FEN),
        GameSpec(1, 0, 9, 40, FENS[1]),
        GameSpec(0, 2, 11, 12, FENS[3]),
        GameSpec(1, 2, 13, 30, FENS[8]),
    )
    val gameJson = games.map { g ->
        val match = ChessMatch(ChessPosition.fromFen(g.fen)!!)
        val random = Random(g.seed)
        val uci = mutableListOf<String>()
        while (!match.isOver && uci.size < g.maxPlies) {
            val level = if (match.position.sideToMove == ChessColor.WHITE) g.white else g.black
            val move = ChessBot.bestMove(match.position, level, random)!!
            match.play(move.from, move.to, move.promotion)!!
            uci.add(move.uci)
        }
        val r = match.result
        "{\"white\":${g.white},\"black\":${g.black},\"seed\":${g.seed},\"maxPlies\":${g.maxPlies},\"start\":${q(g.fen)}," +
            "\"moves\":${arr(uci.map(::q))},\"san\":${arr(match.sanMoves.map(::q))},\"fen\":${q(match.position.fen)}," +
            "\"reason\":${q(r?.reason)},\"winner\":${q(r?.winner?.name)},\"next\":${q(if (match.isOver) null else ChessBot.bestMove(match.position, 0, Random(g.seed + 100))?.uci)}}"
    }
    val best = mutableListOf<String>()
    for (fen in FENS) {
        val p = ChessPosition.fromFen(fen)!!
        for (level in 0..2) {
            val seeds = if (level == 2) listOf(1) else listOf(1, 2, 3)
            for (seed in seeds) {
                val move = ChessBot.bestMove(p, level, Random(seed))
                best.add("{\"fen\":${q(fen)},\"level\":$level,\"seed\":$seed,\"move\":${q(move?.uci)}}")
            }
        }
    }
    val evals = FENS.map { fen ->
        val p = ChessPosition.fromFen(fen)!!
        "{\"fen\":${q(fen)},\"white\":${ChessBot.evaluate(p, ChessColor.WHITE)},\"black\":${ChessBot.evaluate(p, ChessColor.BLACK)}," +
            "\"legal\":${arr(p.legalMoves().map { q(it.uci) })},\"san\":${arr(p.legalMoves().map { q(p.san(it)) })}," +
            "\"insufficient\":${p.hasInsufficientMaterial},\"whiteCanMate\":${p.canMate(ChessColor.WHITE)},\"blackCanMate\":${p.canMate(ChessColor.BLACK)}," +
            "\"repetitionKey\":${q(p.repetitionKey)}}"
    }
    val perft = listOf(
        Triple(FENS[0], 4, 0), Triple(FENS[1], 3, 0), Triple(FENS[2], 4, 0), Triple(FENS[3], 3, 0), Triple(FENS[4], 3, 0),
    ).map { (fen, depth, _) -> "{\"fen\":${q(fen)},\"depth\":$depth,\"nodes\":${ChessPosition.fromFen(fen)!!.perft(depth)}}" }
    return "{\"games\":${arr(gameJson)},\"bestMoves\":${arr(best)},\"positions\":${arr(evals)},\"perft\":${arr(perft)}}"
}

private fun cellsString(board: TicTacToeBoard) = board.cells.joinToString("") { it?.label ?: "." }

private fun ticTacToeGolden(): String {
    val games = mutableListOf<String>()
    val levels = BotLevel.entries
    for (x in levels) for (o in levels) for (starter in TTTMark.entries) for (seed in 0 until 12) {
        val board = TicTacToeBoard(starter)
        val rng = Random(seed)
        val cells = mutableListOf<Int>()
        while (!board.isOver) {
            val level = if (board.turn == TTTMark.X) x else o
            val cell = TicTacToeBot.choose(board, level, rng)!!
            check(board.play(cell))
            cells.add(cell)
        }
        games.add("{\"x\":${q(x.name)},\"o\":${q(o.name)},\"starter\":${q(starter.label)},\"seed\":$seed,\"cells\":${arr(cells.map { "$it" })},\"winner\":${q(board.win?.mark?.label)}}")
    }
    val choices = mutableListOf<String>()
    for (k in 0 until 300) {
        val gen = Random(1000 + k)
        val board = TicTacToeBoard(if (gen.nextBoolean()) TTTMark.X else TTTMark.O)
        val plies = gen.nextInt(0, 8)
        repeat(plies) {
            if (!board.isOver) board.play((0 until 9).filter { board.canPlay(it) }.random(gen))
        }
        val picks = levels.map { TicTacToeBot.choose(board, it, Random(k))?.toString() ?: "null" }
        val best = TicTacToeBot.best(board, Random(k))?.toString() ?: "null"
        choices.add("{\"cells\":${q(cellsString(board))},\"turn\":${q(board.turn.label)},\"easy\":${picks[0]},\"normal\":${picks[1]},\"hard\":${picks[2]},\"best\":$best}")
    }
    return "{\"games\":${arr(games)},\"choices\":${arr(choices)}}"
}

fun main(args: Array<String>) {
    val out = File(args.getOrElse(0) { "." })
    val t0 = System.nanoTime()
    File(out, "TicTacToeGolden.json").writeText(ticTacToeGolden())
    val t1 = System.nanoTime()
    File(out, "ChessGolden.json").writeText(chessGolden())
    val t2 = System.nanoTime()
    System.err.println("tictactoe ${(t1 - t0) / 1_000_000} ms, chess ${(t2 - t1) / 1_000_000} ms")
}
