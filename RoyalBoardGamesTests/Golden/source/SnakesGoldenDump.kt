package com.ngstudio.royalboardgames.game.snakes

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.ngstudio.royalboardgames.game.common.PartyStyle
import org.junit.Test
import java.io.File

/**
 * Golden values for the iOS port (RoyalBoardGamesTests/SnakesGoldenTests.swift): SeededRandom streams,
 * board and snake geometry, 120 complete matches driven by java.util.Random dice (every roll fingerprinted,
 * standings after each roll), the ten board themes and the Compose colour mixes the board art uses.
 * Run: ./gradlew :app:testDebugUnitTest --tests '*SnakesGoldenDump*'
 * Output: app/build/snakes_golden.json (Gradle runs tests in the module directory), or -Dsnakes.golden.out=PATH.
 */
class SnakesGoldenDump {
    private val sb = StringBuilder()

    private fun d(v: Double) = java.lang.Double.doubleToRawLongBits(v).toString()
    private fun argb(c: Color) = (c.toArgb().toLong() and 0xFFFFFFFFL).toString()

    private fun fnv(s: String, h0: Long): Long {
        var h = h0
        for (b in s.toByteArray(Charsets.UTF_8)) {
            h = h xor (b.toLong() and 0xFF)
            h *= 0x100000001b3L
        }
        return h
    }

    private fun seeded() {
        sb.append("\"seeded\":[")
        val seeds = listOf(0L, 1L, 7L, 8L, 9L, 10L, 11L, 12L, 13L, 14L, 15L, 16L, 42L, -1L, -7L, Long.MIN_VALUE, Long.MAX_VALUE)
        seeds.forEachIndexed { i, seed ->
            if (i > 0) sb.append(",")
            val r = SeededRandom(seed)
            sb.append("{\"seed\":$seed,\"values\":${(0 until 400).joinToString(",", "[", "]") { d(r.next()) }}}")
        }
        sb.append("]")
    }

    private fun geometry() {
        sb.append("\"geometry\":{")
        sb.append("\"cells\":${(1..100).joinToString(",", "[", "]") { val (r, c) = SnakesBoard.cell(it); "[$r,$c]" }}")
        sb.append(",\"clamped\":${listOf(-5, 0, 101, 150).joinToString(",", "[", "]") { val (r, c) = SnakesBoard.cell(it); "[$it,$r,$c]" }}")
        sb.append(",\"destinations\":${(0..100).joinToString(",", "[", "]") { "${SnakesBoard.destination(it)}" }}")
        sb.append(",\"ladders\":${SnakesBoard.ladders.entries.joinToString(",", "[", "]") { "[${it.key},${it.value}]" }}")
        sb.append(",\"snakes\":${SnakesBoard.snakes.entries.joinToString(",", "[", "]") { "[${it.key},${it.value}]" }}")
        sb.append(",\"heads\":${SnakesGeometry.snakeHeads.joinToString(",", "[", "]")}")
        sb.append(",\"bottoms\":${SnakesGeometry.ladderBottoms.joinToString(",", "[", "]")}")
        sb.append(",\"centers\":${(1..100).joinToString(",", "[", "]") { val p = SnakesGeometry.center(it); "[${d(p.x)},${d(p.y)}]" }}")
        sb.append(",\"starts\":${(0 until 6).joinToString(",", "[", "]") { val p = SnakesGeometry.startPoint(it); "[${d(p.x)},${d(p.y)}]" }}")
        sb.append(",\"bodies\":[")
        SnakesGeometry.snakeHeads.forEachIndexed { i, head ->
            if (i > 0) sb.append(",")
            val length = SnakesGeometry.snakeLength(head)
            val samples = kotlin.math.max(60, (length * 36).toInt())
            val spine = SnakesGeometry.snakeSpine(head, samples)
            val ride = (1..32).map { SnakesGeometry.snakePoint(head, it.toDouble() / 32) }
            sb.append("{\"head\":$head,\"length\":${d(length)},\"samples\":$samples")
            sb.append(",\"spine\":${spine.joinToString(",", "[", "]") { "[${d(it.x)},${d(it.y)}]" }}")
            sb.append(",\"ride\":${ride.joinToString(",", "[", "]") { "[${d(it.x)},${d(it.y)}]" }}}")
        }
        sb.append("]}")
    }

    private fun moveString(m: SnakesMove): String {
        val j = when (val jump = m.jump) {
            is SnakesMove.Jump.Ladder -> "L${jump.from}>${jump.to}"
            is SnakesMove.Jump.Snake -> "S${jump.from}>${jump.to}"
            null -> "-"
        }
        val o = when (val out = m.outcome) {
            SnakesMove.Outcome.Moved -> "M"
            SnakesMove.Outcome.NeedSix -> "N"
            is SnakesMove.Outcome.Overshoot -> "O${out.needed}"
            SnakesMove.Outcome.ThreeSixes -> "T"
            is SnakesMove.Outcome.Finished -> "F${out.place}"
        }
        return "${m.player} ${m.roll} ${m.from} ${m.steps.joinToString(".")} $j ${m.to} $o ${if (m.extraTurn) 1 else 0} ${m.nextPlayer}"
    }

    private fun traces() {
        sb.append("\"traces\":[")
        var first = true
        for (players in 2..6) for (mask in 0 until 8) for (run in 1..3) {
            val rules = SnakesRules(requireSixToStart = mask and 1 != 0, exactRollToFinish = mask and 2 != 0, extraTurnOnSix = mask and 4 != 0)
            val seed = run * 1000L + players * 10L + mask
            val rnd = java.util.Random(seed)
            val game = SnakesMatch(players, rules)
            val moves = ArrayList<String>()
            var hash = -0x340d631b7bdddcdbL
            while (!game.isOver && moves.size < 5000) {
                val m = game.roll(rnd.nextInt(6) + 1)
                val line = moveString(m) + "|" + game.standings.joinToString(".") + "|" + game.current + "," + game.sixStreak + "," + game.turnCount
                moves.add(line)
                hash = fnv(line + "\n", hash)
            }
            if (!first) sb.append(",")
            first = false
            sb.append("{\"players\":$players,\"rules\":[${rules.requireSixToStart},${rules.exactRollToFinish},${rules.extraTurnOnSix}],\"seed\":$seed")
            sb.append(",\"count\":${moves.size},\"hash\":\"${java.lang.Long.toHexString(hash)}\"")
            // Full move lists for the first run of every player count, to localise any mismatch.
            if (run == 1 && mask == 7) sb.append(",\"moves\":${moves.joinToString(",", "[", "]") { "\"$it\"" }}")
            sb.append(",\"positions\":${game.positions.joinToString(",", "[", "]")},\"finishOrder\":${game.finishOrder.joinToString(",", "[", "]")}")
            sb.append(",\"standings\":${game.standings.joinToString(",", "[", "]")},\"current\":${game.current},\"sixStreak\":${game.sixStreak}")
            sb.append(",\"turnCount\":${game.turnCount},\"isOver\":${game.isOver}}")
        }
        sb.append("]")
    }

    private fun themes() {
        sb.append("\"themes\":[")
        SnakesTheme.all.forEachIndexed { i, t ->
            if (i > 0) sb.append(",")
            sb.append("{\"id\":${t.id},\"name\":\"${t.name}\",\"emoji\":\"${t.emoji}\",\"tagline\":\"${t.tagline}\"")
            sb.append(",\"background\":${t.background.joinToString(",", "[", "]") { argb(it) }},\"frame\":${argb(t.frame)}")
            sb.append(",\"cellA\":${argb(t.cellA)},\"cellB\":${argb(t.cellB)},\"numberColor\":${argb(t.numberColor)},\"numberColorB\":${argb(t.numberColorB)}")
            sb.append(",\"isDark\":${t.isDark},\"snakeColors\":${t.snakeColors.joinToString(",", "[", "]") { pair -> pair.joinToString(",", "[", "]") { argb(it) } }}")
            sb.append(",\"snakePattern\":\"${t.snakePattern.name}\"")
            sb.append(",\"rails\":${t.ladder.rails.joinToString(",", "[", "]") { argb(it) }},\"rung\":${argb(t.ladder.rung)}")
            sb.append(",\"stripe\":${t.ladder.stripe?.let { argb(it) } ?: "null"},\"glow\":${t.ladder.glow?.let { argb(it) } ?: "null"},\"knots\":${t.ladder.knots}")
            sb.append(",\"accent\":${argb(t.accent)},\"backdrop\":\"${t.backdrop.name}\"}")
        }
        sb.append("]")
    }

    private fun mixes() {
        sb.append("\"mixes\":[")
        val cases = ArrayList<String>()
        fun add(base: Color, other: Color, by: Float) {
            cases.add("[${argb(base)},${argb(other)},${java.lang.Float.floatToRawIntBits(by)},${argb(base.mix(other, by))}]")
        }
        val w = Color.White
        val k = Color.Black
        for (t in SnakesTheme.all) {
            add(t.frame, w, 0.3f); add(t.frame, k, 0.32f); add(t.frame, k, 0.5f)
            add(t.cellA, w, 0.25f); add(t.cellB, w, 0.1f); add(t.cellB, k, 0.08f)
            add(t.ladder.rails.lastOrNull() ?: t.ladder.rung, k, 0.5f)
            for (pair in t.snakeColors) {
                val b = pair[0]
                add(b, w, 0.1f); add(b, k, 0.12f); add(b, k, 0.5f); add(b, w, 0.3f); add(b, k, 0.18f); add(b, k, 0.3f)
            }
        }
        for (c in PartyStyle.tokenColors) {
            for ((other, by) in listOf(w to 0.35f, k to 0.25f, k to 0.35f, w to 0.25f, k to 0.22f, w to 0.15f, k to 0.3f, w to 0.2f)) add(c, other, by)
        }
        sb.append(cases.joinToString(","))
        sb.append("]")
    }

    @Test
    fun dump() {
        sb.append("{")
        seeded(); sb.append(",")
        geometry(); sb.append(",")
        traces(); sb.append(",")
        themes(); sb.append(",")
        mixes()
        sb.append("}")
        val out = System.getProperty("snakes.golden.out") ?: File("build", "snakes_golden.json").path
        File(out).writeText(sb.toString())
        println("snakes golden → $out (${sb.length} chars)")
    }
}
