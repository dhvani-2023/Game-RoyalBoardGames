package com.ngstudio.royalboardgames.game.carrom

import org.junit.Test
import java.io.File
import kotlin.math.PI

/**
 * Golden dump for the iOS port: rack, physics runs, bot plans, guides, estimates and whole bot-vs-bot matches, with
 * every Double as raw bits (hex) so Swift can require exact equality.
 *
 * How it was run: the unmodified Android sources CarromBoard/Physics/Rules/Bot/Guide/Store.kt, with only their
 * `import kotlin.math.sin|cos|atan2|ln|pow` lines pointed at CarromStrictTrig.kt (StrictMath = fdlibm), plus
 * stubs for PartyPlayer and Prefs; compiled with kotlinc 2.3 + the serialization plugin and run with JUnit 4 on
 * JBR 25 (aarch64). The original CarromTest suite passes unchanged on that build too.
 */
class CarromGoldenDump {
    private fun hx(d: Double): String = java.lang.Long.toHexString(java.lang.Double.doubleToRawLongBits(d))

    private class Fnv {
        var h = -0x340d631b7bdddcdbL
        fun add(v: Long) {
            for (k in 0 until 8) {
                h = h xor ((v ushr (8 * k)) and 0xffL)
                h *= 0x100000001b3L
            }
        }
        fun d(x: Double) = add(java.lang.Double.doubleToRawLongBits(x))
        fun f(x: Float) = add(java.lang.Float.floatToRawIntBits(x).toLong())
        fun i(x: Int) = add(x.toLong())
        fun hex(): String = java.lang.Long.toHexString(h)
    }

    private fun q(s: String) = "\"" + s + "\""

    private fun discsHash(d: List<CarromDisc>): String {
        val f = Fnv()
        for (c in d) { f.i(c.kind.ordinal); f.d(c.x); f.d(c.y); f.d(c.vx); f.d(c.vy); f.i(if (c.live) 1 else 0) }
        return f.hex()
    }

    private fun tableHash(t: CarromTable): String {
        val f = Fnv()
        for (c in t.coins) { f.i(c.kind.ordinal); f.d(c.x); f.d(c.y); f.i(if (c.live) 1 else 0) }
        f.i(t.turn); f.i(t.strokes); f.i(if (t.broken) 1 else 0); f.i(t.queenWaiting ?: -1); f.i(t.queenCoveredBy ?: -1)
        for (p in t.points) f.i(p)
        for (o in t.owed) f.i(o)
        for (s in t.stats) { f.i(s.coins); f.i(s.points); f.i(s.queens); f.i(s.fouls); f.i(s.bestCombo); f.i(s.strokes) }
        f.i(t.winner ?: -1); f.i(t.boardPoints); f.i(t.target)
        for (w in t.winnerScoreBefore) f.i(w)
        return f.hex()
    }

    private fun kinds(k: List<CarromKind>) = k.joinToString("") { when (it) { CarromKind.WHITE -> "W"; CarromKind.BLACK -> "B"; CarromKind.QUEEN -> "Q"; CarromKind.STRIKER -> "S" } }

    private fun runJson(sim: CarromSimulation): String {
        val run = sim.run
        val ev = Fnv()
        for (e in run.events) {
            ev.i(e.kind.ordinal); ev.d(e.time); ev.d(e.strength); ev.i(e.disc); ev.i(e.other); ev.d(e.at.x); ev.d(e.at.y); ev.i(e.pocket)
        }
        val fr = Fnv()
        for (frame in run.frames) for (v in frame) fr.f(v)
        val sb = StringBuilder("{")
        sb.append("\"final\":").append(q(discsHash(sim.discs))).append(",")
        sb.append("\"striker\":[").append(q(hx(sim.discs[sim.striker].x))).append(",").append(q(hx(sim.discs[sim.striker].y))).append("],")
        sb.append("\"pocketed\":[").append(run.pocketed.joinToString(",") { "[${it.disc},${it.pocket},${q(hx(it.time))}]" }).append("],")
        sb.append("\"events\":").append(run.events.size).append(",")
        sb.append("\"eventHash\":").append(q(ev.hex())).append(",")
        sb.append("\"firstContact\":").append(run.firstContact ?: -1).append(",")
        sb.append("\"duration\":").append(q(hx(run.duration))).append(",")
        sb.append("\"frames\":").append(run.frames.size).append(",")
        sb.append("\"frameHash\":").append(q(fr.hex())).append("}")
        return sb.toString()
    }

    private fun strokeJson(s: CarromStroke): String =
        "{\"seat\":${s.seat},\"pocketed\":${q(kinds(s.pocketed))},\"foul\":${s.foul},\"continues\":${s.continues}," +
            "\"queenCovered\":${s.queenCovered},\"queenWaiting\":${s.queenWaiting},\"queenReturned\":${s.queenReturned}," +
            "\"returned\":${q(kinds(s.returned))},\"queenFirst\":${s.queenFirst},\"points\":${s.points},\"boardOver\":${s.boardOver},\"timedOut\":${s.timedOut}}"

    private fun planJson(p: CarromPlan): String =
        "{\"slide\":${q(hx(p.shot.slide))},\"angle\":${q(hx(p.shot.angle))},\"power\":${q(hx(p.shot.power))},\"target\":${p.target},\"pocket\":${p.pocket}," +
            "\"ghost\":[${q(hx(p.ghost.x))},${q(hx(p.ghost.y))}],\"score\":${q(hx(p.score))}}"

    private fun classic(tournament: Boolean = false): CarromTable {
        val t = CarromTable.create(CarromMode.CLASSIC, listOf(0, 2), teams = false, tournament = tournament, breaker = 0)
        t.broken = true
        return t
    }

    /** The same scattered tables as CarromTest. */
    private fun scattered(seed: ULong): CarromTable {
        val rng = CarromRandom(seed)
        val t = classic()
        val placed = ArrayList<CarromVec>()
        for (i in t.coins.indices) {
            val kind = t.coins[i].kind
            val keep = kind == CarromKind.QUEEN || t.coins.take(i).count { it.kind == kind } < 5
            if (!keep) { t.coins[i].live = false; continue }
            while (true) {
                val p = CarromVec(rng.unit() * 64 - 32, rng.unit() * 52 - 32)
                if (placed.all { (it - p).length > 2 * CarromBoard.coinR + 0.3 } && CarromBoard.pockets.all { (it - p).length > 5 }) {
                    t.coins[i].p = p
                    placed.add(p)
                    break
                }
            }
        }
        return t
    }

    private fun guideJson(g: CarromGuide): String =
        "{\"path\":[${g.path.joinToString(",") { "[${q(hx(it.x))},${q(hx(it.y))}]" }}]," +
            "\"ghost\":${g.ghost?.let { "[${q(hx(it.x))},${q(hx(it.y))}]" } ?: "null"},\"coin\":${g.coin ?: -1}," +
            "\"coinEnd\":${g.coinEnd?.let { "[${q(hx(it.x))},${q(hx(it.y))}]" } ?: "null"},\"pocket\":${g.pocket ?: -1}}"

    private fun game(name: String, options: CarromOptions, seats: Int, levels: List<CarromDifficulty>, gi: Int): String {
        val m = CarromMatch.create(options, seats, 0)
        val strokes = ArrayList<String>()
        var k = 0
        while (!m.isOver && k < 400) {
            val t = m.table
            if (t.winner != null) {
                m.finishBoard()
                if (m.isOver) break
                m.nextBoard()
                strokes.add("{\"nextBoard\":${m.board},\"turn\":${m.table.turn},\"hash\":${q(tableHash(m.table))}}")
                continue
            }
            val level = levels[t.turn]
            val seed = (gi * 7919 + k * 31 + 1).toULong()
            val plan = CarromBot.plan(t, level, seed)
            val shot = CarromShot(t.freeSlide(plan.shot.slide), plan.shot.angle, plan.shot.power)
            val s = t.play(shot)
            strokes.add("{\"plan\":${planJson(plan)},\"stroke\":${strokeJson(s)},\"hash\":${q(tableHash(t))}}")
            k += 1
        }
        val sb = StringBuilder("{")
        sb.append("\"name\":${q(name)},\"seats\":$seats,\"mode\":${q(options.mode.name)},\"length\":${q(options.length.name)},")
        sb.append("\"tournament\":${options.tournament},\"freestyleTeams\":${options.freestyleTeams},")
        sb.append("\"levels\":[${levels.joinToString(",") { q(it.name) }}],\"gi\":$gi,")
        sb.append("\"steps\":[${strokes.joinToString(",\n")}],")
        sb.append("\"winner\":${m.winner ?: -1},\"board\":${m.board},\"scores\":${m.scores},\"wins\":${m.wins},")
        sb.append("\"totals\":[${m.totals.joinToString(",") { "[${it.coins},${it.points},${it.queens},${it.fouls},${it.bestCombo},${it.strokes}]" }}]}")
        return sb.toString()
    }

    @Test
    fun dump() {
        val out = StringBuilder("{\n")

        // Constants and the rack.
        val consts = listOf(
            "pocketR" to CarromBoard.pocketR, "pocketC" to CarromBoard.pocketC, "coinR" to CarromBoard.coinR, "strikerR" to CarromBoard.strikerR,
            "baseOuter" to CarromBoard.baseOuter, "baseInner" to CarromBoard.baseInner, "baseY" to CarromBoard.baseY, "slideMax" to CarromBoard.slideMax,
            "outerR" to CarromBoard.outerR, "dt" to CarromPhysics.dt,
        )
        out.append("\"constants\":{${consts.joinToString(",") { "${q(it.first)}:${q(hx(it.second))}" }}},\n")
        out.append("\"rack\":[${CarromBoard.rack(true).joinToString(",") { "[${q(it.kind.name)},${q(hx(it.x))},${q(hx(it.y))}]" }}],\n")
        out.append("\"rackNoQueen\":${q(discsHash(CarromBoard.rack(false)))},\n")
        val spots = ArrayList<String>()
        for (side in 0 until 4) for (slide in listOf(-1.0, -0.37, 0.0, 0.5, 1.0)) {
            val p = CarromBoard.strikerSpot(side, slide)
            spots.add("[${q(hx(p.x))},${q(hx(p.y))},${q(hx(CarromBoard.slide(p, side)))},${q(hx(CarromBoard.distanceToBaseLine(CarromVec(3.3, 20.1), side)))}]")
        }
        out.append("\"spots\":[${spots.joinToString(",")}],\n")
        val aims = ArrayList<String>()
        for (side in 0 until 4) for (a in listOf(-3.0, -PI / 2, 0.0, 1.0, 2.5, PI, 4.0)) aims.add(q(hx(CarromBoard.clampAim(a, side))))
        out.append("\"clampAim\":[${aims.joinToString(",")}],\n")
        val rack = CarromBoard.rack(true)
        val fs = CarromBoard.freeSpot(avoiding = rack)
        val fs2 = CarromBoard.freeSpot(CarromVec(5.0, -3.0), rack)
        out.append("\"freeSpot\":[${q(hx(fs.x))},${q(hx(fs.y))},${q(hx(fs2.x))},${q(hx(fs2.y))}],\n")

        // Random numbers.
        val r = CarromRandom(42uL)
        val raws = (0 until 4).map { java.lang.Long.toHexString(r.next().toLong()) }
        val units = (0 until 4).map { hx(r.unit()) }
        val normals = (0 until 6).map { hx(r.normal()) }
        out.append("\"random\":{\"next\":[${raws.joinToString(",") { q(it) }}],\"unit\":[${units.joinToString(",") { q(it) }}],\"normal\":[${normals.joinToString(",") { q(it) }}]},\n")

        // Planning helpers.
        val helpers = ArrayList<String>()
        for (v in listOf(0.0, 1.0, 10.0, 50.0, 123.4, 300.0)) helpers.add(q(hx(CarromPhysics.travel(v))))
        for (x in listOf(1.0, 10.0, 55.5, 100.0)) helpers.add(q(hx(CarromPhysics.speedToTravel(x))))
        helpers.add(q(hx(CarromPhysics.launch(100.0, 30.0))))
        for (p in listOf(0.0, 0.02, 0.3, 0.5, 0.93, 1.0)) helpers.add(q(hx(CarromPhysics.speedForPower(p))))
        for (s in listOf(0.0, 10.0, 150.0, 299.0, 400.0)) helpers.add(q(hx(CarromPhysics.powerForSpeed(s))))
        out.append("\"helpers\":[${helpers.joinToString(",")}],\n")

        // fdlibm self-check: the iOS port of StrictMath must give the same bits on many inputs.
        val fr = CarromRandom(2026uL)
        val hSin = Fnv(); val hCos = Fnv(); val hAtan2 = Fnv(); val hLog = Fnv(); val hPow = Fnv(); val hPowInv = Fnv()
        for (i in 0 until 200_000) {
            val x = (fr.unit() - 0.5) * 20
            val y = (fr.unit() - 0.5) * 20
            val p = fr.unit() * 400
            val b = fr.unit()
            hSin.d(StrictMath.sin(x)); hCos.d(StrictMath.cos(x)); hAtan2.d(StrictMath.atan2(y, x)); hLog.d(StrictMath.log(p))
            hPow.d(StrictMath.pow(b, 1.8)); hPowInv.d(StrictMath.pow(b, 1 / 1.8))
        }
        out.append("\"fdlibm\":{\"n\":200000,\"sin\":${q(hSin.hex())},\"cos\":${q(hCos.hex())},\"atan2\":${q(hAtan2.hex())},\"log\":${q(hLog.hex())},\"pow\":${q(hPow.hex())},\"powInv\":${q(hPowInv.hex())}},\n")

        // Physics runs on the opening rack and from other sides.
        val shots = listOf(
            CarromShot(0.0, -PI / 2, 1.0), CarromShot(0.12, -1.5, 0.97), CarromShot(-0.6, -1.2, 0.8), CarromShot(0.9, -2.2, 0.5),
            CarromShot(0.3, -PI / 2 + 0.05, 0.3), CarromShot(-1.0, -0.4, 1.0), CarromShot(0.05, -1.62, 0.01),
        )
        val runs = ArrayList<String>()
        for (shot in shots) {
            val t = CarromTable.create(CarromMode.CLASSIC, listOf(0, 2), false, false, 0)
            val sim = t.simulate(shot, true)
            val stroke = t.play(shot)
            runs.add("{\"table\":\"classic\",\"shot\":[${q(hx(shot.slide))},${q(hx(shot.angle))},${q(hx(shot.power))}],\"run\":${runJson(sim)},\"stroke\":${strokeJson(stroke)},\"hash\":${q(tableHash(t))}}")
        }
        val side1 = listOf(CarromShot(0.0, PI, 1.0), CarromShot(-0.4, 2.7, 0.9), CarromShot(0.7, -2.9, 0.75))
        for (shot in side1) {
            val t = CarromTable.create(CarromMode.FREESTYLE, listOf(0, 1, 2, 3), true, false, 1)
            val sim = t.simulate(shot, true)
            val stroke = t.play(shot)
            runs.add("{\"table\":\"teams1\",\"shot\":[${q(hx(shot.slide))},${q(hx(shot.angle))},${q(hx(shot.power))}],\"run\":${runJson(sim)},\"stroke\":${strokeJson(stroke)},\"hash\":${q(tableHash(t))}}")
        }
        for (seed in 1uL..4uL) {
            val t = scattered(seed * 101uL)
            val shot = CarromShot(-0.5 + seed.toDouble() * 0.2, -PI / 2 + (seed.toDouble() - 2.5) * 0.3, 0.6 + seed.toDouble() * 0.08)
            val sim = t.simulate(shot, true)
            val stroke = t.play(shot)
            runs.add("{\"table\":\"scattered${seed * 101uL}\",\"shot\":[${q(hx(shot.slide))},${q(hx(shot.angle))},${q(hx(shot.power))}],\"run\":${runJson(sim)},\"stroke\":${strokeJson(stroke)},\"hash\":${q(tableHash(t))}}")
        }
        out.append("\"runs\":[\n${runs.joinToString(",\n")}],\n")

        // Scattered tables and bot plans.
        val tables = ArrayList<String>()
        for (seed in listOf(1uL, 2uL, 31uL, 62uL, 101uL)) tables.add("{\"seed\":$seed,\"hash\":${q(tableHash(scattered(seed)))}}")
        out.append("\"scattered\":[${tables.joinToString(",")}],\n")
        val cands = CarromBot.candidates(scattered(1uL))
        out.append("\"candidates\":{\"count\":${cands.size},\"top\":[${cands.take(8).joinToString(",") { planJson(it) }}]},\n")
        val plans = ArrayList<String>()
        for (seed in 1uL..6uL) {
            val t = scattered(seed)
            plans.add("{\"table\":$seed,\"level\":\"NORMAL\",\"seed\":$seed,\"plan\":${planJson(CarromBot.plan(t, CarromDifficulty.NORMAL, seed))}}")
        }
        for (seed in 1uL..10uL) {
            val t = scattered(seed * 31uL)
            for (level in listOf(CarromDifficulty.EASY, CarromDifficulty.HARD)) {
                val plan = CarromBot.plan(t, level, seed)
                val after = t.deepCopy()
                val s = after.play(plan.shot)
                plans.add("{\"table\":${seed * 31uL},\"level\":${q(level.name)},\"seed\":$seed,\"plan\":${planJson(plan)},\"stroke\":${strokeJson(s)},\"hash\":${q(tableHash(after))}}")
            }
        }
        val fresh = CarromTable.create(CarromMode.CLASSIC, listOf(0, 2), false, false, 0)
        for (level in CarromDifficulty.entries) for (seed in listOf(7uL, 99uL)) {
            plans.add("{\"table\":0,\"level\":${q(level.name)},\"seed\":$seed,\"plan\":${planJson(CarromBot.plan(fresh, level, seed))}}")
        }
        val safe = CarromBot.safety(scattered(2uL))
        plans.add("{\"table\":-2,\"level\":\"SAFETY\",\"seed\":0,\"plan\":${planJson(safe)}}")
        out.append("\"plans\":[\n${plans.joinToString(",\n")}],\n")

        // Aim guides.
        val guides = ArrayList<String>()
        val gt = CarromTable.create(CarromMode.CLASSIC, listOf(0, 2), false, false, 0)
        val gs = scattered(62uL)
        for ((table, tn) in listOf(gt to 0, gs to 62)) {
            for ((slide, angle) in listOf(0.0 to -PI / 2, 0.5 to -2.0, -0.8 to -0.3, 1.0 to -0.05, -0.2 to -1.9, 0.7 to -PI + 0.2)) {
                for (style in CarromAimGuide.entries) {
                    guides.add("{\"table\":$tn,\"slide\":${q(hx(slide))},\"angle\":${q(hx(angle))},\"style\":${q(style.name)},\"guide\":${guideJson(CarromGuide.compute(table, slide, angle, style))}}")
                }
            }
        }
        out.append("\"guides\":[\n${guides.joinToString(",\n")}],\n")

        // Table helpers on a scattered table.
        val ht = scattered(31uL)
        val fits = (0..20).map { ht.strikerFits(-1 + it * 0.1) }
        val free = listOf(-1.0, -0.5, 0.0, 0.33, 1.0).map { q(hx(ht.freeSlide(it))) }
        out.append("\"tableHelpers\":{\"targets\":${ht.targets()},\"fits\":$fits,\"free\":[${free.joinToString(",")}]},\n")

        // Estimates.
        val est = ArrayList<Int>()
        for (seats in 2..4) for (people in 0..seats) for (mode in CarromMode.entries) for (length in CarromMatchLength.entries) for (fast in listOf(false, true)) {
            est.add(CarromStore.estimatedMinutes(seats, people, CarromOptions(mode = mode, length = length, fastBots = fast)))
        }
        out.append("\"estimates\":$est,\n")

        // Whole matches between computers.
        val n = CarromDifficulty.NORMAL
        val games = listOf(
            game("classic2", CarromOptions(), 2, listOf(n, n), 1),
            game("pool2", CarromOptions(mode = CarromMode.POOL), 2, listOf(n, n), 2),
            game("free3", CarromOptions(mode = CarromMode.FREESTYLE), 3, listOf(n, n, n), 3),
            game("teams4t", CarromOptions(tournament = true), 4, listOf(n, n, n, n), 4),
            game("free4", CarromOptions(mode = CarromMode.FREESTYLE), 4, listOf(n, CarromDifficulty.EASY, n, CarromDifficulty.EASY), 5),
            game("classic2bo3", CarromOptions(length = CarromMatchLength.BEST_OF_THREE), 2, listOf(CarromDifficulty.EASY, CarromDifficulty.HARD), 6),
            game("free4teams", CarromOptions(mode = CarromMode.FREESTYLE, freestyleTeams = true, length = CarromMatchLength.RACE25), 4, listOf(n, n, n, n), 7),
            game("classic2t", CarromOptions(tournament = true, length = CarromMatchLength.RACE25), 2, listOf(n, CarromDifficulty.EASY), 8),
        )
        out.append("\"games\":[\n${games.joinToString(",\n")}]\n")
        out.append("}\n")
        File("/private/tmp/claude-501/-Users-ngd-vi--claude-spares-spare-i6ZDWN/994b964a-4e20-4a95-81be-8ff2ef2b19ea/scratchpad/carrom-rbg/golden/carrom_golden.json").writeText(out.toString())
    }
}
