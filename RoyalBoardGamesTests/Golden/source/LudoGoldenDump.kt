package com.ngstudio.royalboardgames.game.ludo

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import org.junit.Test
import java.io.File

/**
 * Golden values for the iOS port (RoyalBoardGamesTests/LudoGoldenTests.swift): SeededDice streams,
 * board geometry, bot scores, whole seeded bot games (every roll and move), time estimates and
 * Compose colour mixes. Run: ./gradlew :app:testDebugUnitTest --tests '*LudoGoldenDump*'
 * Output: ${java.io.tmpdir}/ludo_golden.json (or -Dludo.golden.out=PATH).
 */
class LudoGoldenDump {
    private val sb = StringBuilder()

    private fun d(v: Double) = java.lang.Double.doubleToRawLongBits(v).toString()
    private fun p(pt: LPoint) = "[${pt.x},${pt.y}]"

    private fun dice() {
        sb.append("\"dice\":[")
        val seeds = listOf(0L, 1L, 3L, 42L, 99L, 100L, 105L, 199L, -7L, Long.MIN_VALUE, Long.MAX_VALUE)
        seeds.forEachIndexed { i, seed ->
            if (i > 0) sb.append(",")
            val a = SeededDice(seed)
            val next = (0 until 8).map { a.next() }
            val b = SeededDice(seed)
            val rolls = (0 until 24).map { b.roll() }
            val c = SeededDice(seed)
            val doubles = (0 until 6).map { d(c.nextDouble()) }
            val e = SeededDice(seed)
            val bounds = listOf(1, 2, 3, 4, 5, 6, 7, 10, 13, 16, 100, 1000, Int.MAX_VALUE)
            val ints = bounds.map { e.nextInt(it) }
            val f = SeededDice(seed)
            val picks = (0 until 10).map { listOf(10, 20, 30, 40).random(f) }
            sb.append("{\"seed\":$seed,\"next\":${next.joinToString(",", "[", "]")},\"rolls\":${rolls.joinToString(",", "[", "]")}")
            sb.append(",\"doubles\":${doubles.joinToString(",", "[", "]")},\"bounds\":${bounds.joinToString(",", "[", "]")},\"ints\":${ints.joinToString(",", "[", "]")}")
            sb.append(",\"picks\":${picks.joinToString(",", "[", "]")}}")
        }
        sb.append("]")
    }

    private fun geometry() {
        sb.append("\"geometry\":[")
        for ((gi, arms) in listOf(4, 6).withIndex()) {
            if (gi > 0) sb.append(",")
            val g = LudoGeometry(arms)
            sb.append("{\"arms\":$arms,\"trackLength\":${g.trackLength},\"lastTrackStep\":${g.lastTrackStep},\"homeStep\":${g.homeStep}")
            sb.append(",\"inner\":${g.inner},\"radius\":${g.radius},\"yardPlateRadius\":${g.yardPlateRadius}")
            sb.append(",\"track\":${(0 until g.trackLength).joinToString(",", "[", "]") { p(g.trackPoint(it)) }}")
            sb.append(",\"cells\":${(0 until g.trackLength).joinToString(",", "[", "]") { val c = g.cell(it); "[${c.arm},${c.v},${c.u}]" }}")
            sb.append(",\"centre\":${g.centreOutline.joinToString(",", "[", "]") { p(it) }}")
            sb.append(",\"perArm\":[")
            for (arm in 0 until arms) {
                if (arm > 0) sb.append(",")
                val dir = g.direction(arm)
                val lat = g.lateral(arm)
                sb.append("{\"direction\":[${dir.dx},${dir.dy}],\"lateral\":[${lat.dx},${lat.dy}]")
                sb.append(",\"route\":${(-1..g.homeStep).joinToString(",", "[", "]") { p(g.routePoint(arm, it)) }}")
                sb.append(",\"trackIndex\":${(-1..g.homeStep).joinToString(",", "[", "]") { "${g.trackIndex(arm, it) ?: -1}" }}")
                sb.append(",\"yard\":${g.yard(arm).joinToString(",", "[", "]") { p(it) }}")
                sb.append(",\"yardCenter\":${p(g.yardCenter(arm))}")
                sb.append(",\"yardSpots\":${(0 until 4).joinToString(",", "[", "]") { p(g.yardSpot(arm, it)) }}")
                val homes = ArrayList<String>()
                for (of in 1..4) for (slot in 0 until of) homes += p(g.homeSpot(arm, slot, of))
                sb.append(",\"homeSpots\":${homes.joinToString(",", "[", "]")}")
                sb.append(",\"triangle\":${g.homeTriangle(arm).joinToString(",", "[", "]") { p(it) }}")
                sb.append(",\"hexVertex\":${p(g.hexVertex(arm))}")
                val corners = ArrayList<String>()
                for (v in 0 until 6) for (u in -1..1) corners += g.cellCorners(arm, v, u).joinToString(",", "[", "]") { p(it) }
                sb.append(",\"cellCorners\":${corners.joinToString(",", "[", "]")}")
                sb.append(",\"shift\":${g.shift(arm)}")
                val t = LudoTransform(g, g.shift(arm), 390.0, 520.0)
                sb.append(",\"cell\":${t.cell},\"screenYard\":${p(t.screen(g.yardCenter(arm)))},\"boardBack\":${p(t.board(t.screen(g.yardCenter(arm))))}}")
            }
            sb.append("]}")
        }
        sb.append("],\"defaultArms\":[")
        var first = true
        for (arms in listOf(4, 6)) for (seats in 2..6) {
            if (!first) sb.append(",")
            first = false
            sb.append("{\"arms\":$arms,\"seats\":$seats,\"value\":${LudoGeometry.defaultArms(seats, arms).joinToString(",", "[", "]")}}")
        }
        sb.append("]")
    }

    private fun rulesJson(r: LudoRules) =
        "{\"quick\":${r.quick},\"allPlaces\":${r.allPlaces},\"oneOrSix\":${r.oneOrSix},\"captureBonus\":${r.captureBonus},\"blockades\":${r.blockades},\"safeStars\":${r.safeStars}}"

    private class GameSpec(
        val name: String, val seed: Long, val arms: Int, val seatArms: List<Int>, val rules: LudoRules,
        val difficulties: List<LudoDifficulty>, val easyAlwaysRandom: Boolean, val scores: Boolean,
    )

    /** The JUnit suite's `playGame`, generalised; returns a full trace of every roll and move. */
    private fun game(spec: GameSpec, first: Boolean) {
        val e = LudoEngine(spec.arms, spec.seatArms, spec.rules)
        val dice = SeededDice(spec.seed)
        val random = SeededDice(spec.seed + 99)
        val trace = ArrayList<String>()
        val scores = ArrayList<String>()
        var guard = 0
        while (!e.isOver && guard < 4000) {
            guard += 1
            val seat = e.current
            val value = dice.roll()
            val outcome = e.roll(value)
            when (outcome) {
                is LudoEngine.RollOutcome.Moves -> {
                    val m = outcome.moves
                    val difficulty = spec.difficulties[e.current]
                    if (spec.scores && m.size > 1 && scores.size < 400) {
                        for (mv in m) scores += "[${mv.token},${mv.to},${d(LudoBot.score(mv, e, difficulty))}]"
                    }
                    val move = if (spec.easyAlwaysRandom && difficulty == LudoDifficulty.EASY && random.roll() <= 6) m.random(random) else LudoBot.choose(m, e, difficulty, random)!!
                    val r = e.apply(move)
                    trace += "$seat:$value:${move.token}>${move.to}${if (move.captures.isNotEmpty()) "x" + move.captures.size else ""}${if (r.extraRoll) "+" else ""}"
                }
                is LudoEngine.RollOutcome.NoMoves -> trace += "$seat:$value:${if (outcome.again) "A" else "N"}"
                LudoEngine.RollOutcome.ThreeSixes -> trace += "$seat:$value:T"
            }
        }
        if (!first) sb.append(",")
        sb.append("{\"name\":\"${spec.name}\",\"seed\":${spec.seed},\"arms\":${spec.arms},\"seatArms\":${spec.seatArms.joinToString(",", "[", "]")}")
        sb.append(",\"rules\":${rulesJson(spec.rules)},\"difficulties\":${spec.difficulties.joinToString(",", "[", "]") { "\"${it.name}\"" }},\"easyAlwaysRandom\":${spec.easyAlwaysRandom}")
        sb.append(",\"guard\":$guard,\"isOver\":${e.isOver},\"turnCount\":${e.turnCount},\"current\":${e.current},\"ranks\":${e.ranks.joinToString(",", "[", "]")},\"standings\":${e.standings.joinToString(",", "[", "]")}")
        sb.append(",\"steps\":${e.steps.joinToString(",", "[", "]") { it.joinToString(",", "[", "]") }}")
        sb.append(",\"stats\":${e.stats.joinToString(",", "[", "]") { "[${it.rolls},${it.sixes},${it.captures},${it.captured},${it.recent.joinToString(",", "[", "]")}]" }}")
        sb.append(",\"trace\":\"${trace.joinToString(",")}\"")
        if (spec.scores) sb.append(",\"scores\":${scores.joinToString(",", "[", "]")}")
        sb.append("}")
    }

    private fun games() {
        val H = LudoDifficulty.HARD
        val N = LudoDifficulty.NORMAL
        val E = LudoDifficulty.EASY
        val specs = ArrayList<GameSpec>()
        // The JUnit suite's own games.
        for (seed in 1..6) specs += GameSpec("legal$seed", seed.toLong(), 4, listOf(0, 1, 2, 3), LudoRules(quick = true), listOf(H, N, E, N), true, seed == 1)
        for (i in 0 until 60) specs += GameSpec("hardVsRandom$i", i + 100L, 4, listOf(0, 1, 2, 3), LudoRules(quick = true), listOf(H, E, E, E), true, false)
        // Wider coverage: classic, six arms, every rule toggle, bot-only easy.
        specs += GameSpec("classic4", 7L, 4, listOf(0, 1, 2, 3), LudoRules(), listOf(H, N, E, H), false, true)
        specs += GameSpec("classic2", 8L, 4, listOf(0, 2), LudoRules(), listOf(N, H), false, true)
        specs += GameSpec("blockades", 9L, 4, listOf(0, 1, 2, 3), LudoRules(blockades = true), listOf(N, N, H, H), false, true)
        specs += GameSpec("oneOrSix", 10L, 4, listOf(0, 1, 2), LudoRules(oneOrSix = true, captureBonus = false), listOf(E, N, H), false, false)
        specs += GameSpec("allPlaces", 11L, 4, listOf(0, 1, 2, 3), LudoRules(quick = true, allPlaces = true), listOf(H, N, E, N), false, false)
        specs += GameSpec("noStars", 12L, 4, listOf(0, 1, 2, 3), LudoRules(safeStars = false), listOf(N, H, N, H), false, false)
        specs += GameSpec("six5", 13L, 6, listOf(0, 1, 2, 3, 4), LudoRules(quick = true), listOf(H, N, E, H, N), false, true)
        specs += GameSpec("six6", 14L, 6, listOf(0, 1, 2, 3, 4, 5), LudoRules(), listOf(N, H, E, N, H, E), false, false)
        specs += GameSpec("six3blockAll", 15L, 6, listOf(0, 2, 4), LudoRules(blockades = true, allPlaces = true, oneOrSix = true), listOf(H, H, N), false, false)
        specs += GameSpec("six2", 16L, 6, listOf(0, 3), LudoRules(quick = true, safeStars = false), listOf(E, H), false, false)
        sb.append("\"games\":[")
        specs.forEachIndexed { i, s -> game(s, i == 0) }
        sb.append("]")
    }

    private fun threats() {
        // Threat and score on a mid-game board, for every square.
        val e = LudoEngine(4, listOf(0, 1, 2, 3), LudoRules())
        e.steps = listOf(listOf(-1, 5, 20, 56), listOf(3, 14, -1, 40), listOf(0, 0, 33, 51), listOf(-1, -1, 9, 47))
        val g = e.geometry
        sb.append("\"threats\":{\"steps\":${e.steps.joinToString(",", "[", "]") { it.joinToString(",", "[", "]") }}")
        for (exact in listOf(false, true)) {
            sb.append(",\"${if (exact) "exact" else "count"}\":[")
            for (seat in 0 until 4) {
                if (seat > 0) sb.append(",")
                sb.append((0 until g.trackLength).joinToString(",", "[", "]") { d(LudoBot.threat(it, seat, e, exact)) })
            }
            sb.append("]")
        }
        sb.append("}")
    }

    private fun estimates() {
        sb.append("\"estimates\":[")
        var first = true
        for (seats in 2..6) for (people in 1..seats) for (arms in listOf(4, 6)) for (mask in 0 until 8) {
            val rules = LudoRules(quick = mask and 1 != 0, allPlaces = mask and 2 != 0, fastBots = mask and 4 != 0)
            if (!first) sb.append(",")
            first = false
            sb.append("[$seats,$people,$arms,$mask,${LudoStore.estimatedMinutes(seats, people, arms, rules)}]")
        }
        sb.append("]")
    }

    private fun colors() {
        sb.append("\"colors\":[")
        val bases = LudoTheme.all.flatMap { it.four + it.six }.distinct() + listOf(0xB9B4C8L, 0xA8A2BCL, 0xFFC94AL, 0x1C1B29L)
        val others = listOf(Color.White, Color.Black, hex(0xE6E2F0))
        val amounts = listOf(0.15f, 0.2f, 0.22f, 0.25f, 0.28f, 0.3f, 0.32f, 0.35f, 0.55f, 0.62f, 0.8f, 1f)
        var first = true
        for (b in bases) for ((oi, o) in others.withIndex()) for (a in amounts) {
            if (!first) sb.append(",")
            first = false
            sb.append("[$b,$oi,$a,${hex(b).mix(o, a).toArgb()}]")
        }
        // Alpha mixes, as the board draws them.
        for (b in bases.take(6)) for (a in listOf(0.0f, 0.3f, 0.6f)) {
            sb.append(",[$b,3,$a,${hex(b).copy(alpha = 0.4f).mix(Color.Black, a).toArgb()}]")
        }
        sb.append("]")
    }

    @Test
    fun dump() {
        sb.append("{\n")
        dice(); sb.append(",\n")
        geometry(); sb.append(",\n")
        threats(); sb.append(",\n")
        estimates(); sb.append(",\n")
        colors(); sb.append(",\n")
        games(); sb.append("\n}\n")
        val out = File(System.getProperty("ludo.golden.out") ?: "/private/tmp/claude-501/-Users-ngd-vi--claude-spares-spare-i6ZDWN/994b964a-4e20-4a95-81be-8ff2ef2b19ea/scratchpad/ludo/ludo_golden.json")
        out.writeText(sb.toString())
        println("wrote ${out.absolutePath} (${sb.length} chars)")
    }
}
