// Pool golden dump for the iOS port (output: RoyalBoardGamesTests/Golden/pool_golden.json, checked by PoolGoldenTests.swift).
// Inputs: the Android sources game/pool/{PoolMath,PoolTable,PoolPhysics,PoolRules,PoolBot}.kt plus verbatim copies of
// PoolGuide (PoolSession.kt) and PoolStore.estimatedMinutes (PoolStore.kt), compiled with kotlin-compiler-embeddable 2.2.10
// (offline; the Android build could not resolve AGP 9.3.3) and run as a main on JBR 25 aarch64 with
//   java -XX:+UnlockDiagnosticVMOptions -XX:DisableIntrinsic=_dsin,_dcos ...
// so Math.sin/cos are fdlibm (StrictMath) like every other kotlin.math function on that JVM. The iOS engine uses
// the same fdlibm (Game/Pool/PoolStrictMath.swift), so every value matches bit for bit.
package com.ngstudio.royalboardgames.game.pool


import java.io.File
import kotlin.math.atan2

/**
 * Golden dump for the iOS port: racks, orientations, geometry, physics traces, rules outcomes,
 * computer plans and the aim guide, with every Double/Float as its raw bit pattern (hex).
 * Output: $GOLDEN_OUT/pool_golden.json (or build/pool_golden.json).
 */
object PoolGoldenDump {
    private val R = PoolTableGeometry.R

    private class H {
        var h = -0x340d631b7bdddcdbL
        fun add(v: Long) { h = (h xor v) * 0x100000001b3L }
        fun d(x: Double) = add(java.lang.Double.doubleToRawLongBits(x))
        fun f(x: Float) = add(java.lang.Float.floatToRawIntBits(x).toLong())
        fun i(x: Int) = add(x.toLong())
        fun hex() = java.lang.Long.toHexString(h)
    }

    private fun b(x: Double) = "\"" + java.lang.Long.toHexString(java.lang.Double.doubleToRawLongBits(x)) + "\""
    private fun vec(v: Vec2?) = if (v == null) "null" else "[${b(v.x)},${b(v.y)}]"
    private fun ints(l: List<Int>) = l.joinToString(",", "[", "]")

    private fun scattered(seed: Long, game: PoolVariant = PoolVariant.EIGHT, size: PoolTableSize = PoolTableSize.BAR): PoolTableState {
        val t = PoolTableState.create(game, PoolOptions(tableSize = size), 2, 0, 1)
        val rng = PoolRandom(seed)
        val geo = t.geometry
        val placed = ArrayList<Vec2>()
        for (ball in t.balls) {
            var p: Vec2
            do {
                p = Vec2((rng.unit() * 2 - 1) * (geo.a - 2 * R), (rng.unit() * 2 - 1) * (geo.b - 2 * R))
            } while (placed.any { (it - p).length < 2 * R + 0.5 })
            placed.add(p)
            ball.p = p
        }
        t.broken = true
        t.ballInHand = false
        t.kitchenOnly = false
        return t
    }

    private fun ballsJson(balls: List<PoolBall>) = balls.joinToString(",", "[", "]") {
        "[${it.n},${b(it.x)},${b(it.y)},${b(it.vx)},${b(it.vy)},${b(it.wx)},${b(it.wy)},${b(it.wz)},${it.live}]"
    }

    private fun shotJson(s: PoolShot) =
        "{\"angle\":${b(s.angle)},\"power\":${b(s.power)},\"spin\":${vec(s.spin)},\"place\":${vec(s.place)},\"call\":${s.call ?: "null"}}"

    private fun tableJson(t: PoolTableState) = buildString {
        append("{\"game\":\"${t.game}\",\"size\":\"${t.size}\",\"seats\":${t.seats},\"turn\":${t.turn},\"broken\":${t.broken},")
        append("\"ballInHand\":${t.ballInHand},\"kitchenOnly\":${t.kitchenOnly},\"groups\":${t.groups.joinToString(",", "[", "]") { if (it == null) "null" else "\"$it\"" }},")
        append("\"winner\":${t.winner ?: "null"},\"foulStreak\":${ints(t.foulStreak)},\"shots\":${t.shots},\"streak\":${t.streak},\"breakVisit\":${t.breakVisit},")
        append("\"stats\":${t.stats.joinToString(",", "[", "]") { "[${it.potted},${it.fouls},${it.bestRun},${it.breakAndRuns},${it.shots}]" }},")
        append("\"balls\":${ballsJson(t.balls)}}")
    }

    /** One physics case: the run, the rules outcome and the rolled orientations. */
    private fun caseJson(name: String, table: PoolTableState, shot: PoolShot): String {
        val (balls, run) = table.simulate(shot, true)
        val ev = H()
        for (e in run.events) {
            ev.i(e.kind.ordinal); ev.d(e.time); ev.d(e.strength); ev.i(e.ball); ev.i(e.other); ev.d(e.at.x); ev.d(e.at.y); ev.i(e.pocket)
        }
        val fr = H()
        for (f in run.frames) for (v in f) fr.f(v)
        // The session's orientation playback.
        val q = table.balls.map { PoolQuat.start(it.n) }.toMutableList()
        val tq = H()
        for (f in run.frames.indices) {
            if (f > 0) {
                val a = run.frames[f]
                val bb = run.frames[f - 1]
                for (i in q.indices) {
                    val dx = a[2 * i] - bb[2 * i]
                    val dy = a[2 * i + 1] - bb[2 * i + 1]
                    if (dx != 0f || dy != 0f) q[i] = PoolQuat.roll(q[i], dx.toDouble(), dy.toDouble())
                }
            }
            for (i in q.indices) { tq.f(q[i].x.toFloat()); tq.f(q[i].y.toFloat()); tq.f(q[i].z.toFloat()); tq.f(q[i].w.toFloat()) }
        }
        val after = table.clone()
        val legal = after.legalFirst()
        val stroke = after.apply(balls, run, shot, legal)
        return buildString {
            append("{\"name\":\"$name\",\"shot\":${shotJson(shot)},")
            append("\"balls\":${ballsJson(balls)},")
            append("\"potted\":${run.potted.joinToString(",", "[", "]") { "[${it.ball},${it.pocket},${b(it.time)}]" }},")
            append("\"firstHit\":${run.firstHit ?: "null"},\"rail\":${run.railAfterContact},\"cushionBalls\":${ints(run.cushionBalls.sorted())},")
            append("\"duration\":${b(run.duration)},\"events\":${run.events.size},\"eventsHash\":\"${ev.hex()}\",")
            append("\"frames\":${run.frames.size},\"framesHash\":\"${fr.hex()}\",\"turnsHash\":\"${tq.hex()}\",")
            append("\"finalQuats\":${q.joinToString(",", "[", "]") { "[${b(it.x)},${b(it.y)},${b(it.z)},${b(it.w)}]" }},")
            append("\"stroke\":{\"seat\":${stroke.seat},\"potted\":${ints(stroke.potted)},\"foul\":${stroke.foul},\"why\":\"${stroke.why}\",\"continues\":${stroke.continues},")
            append("\"rackOver\":${stroke.rackOver},\"won\":${stroke.won},\"groupsSet\":${stroke.groupsSet?.let { "\"$it\"" } ?: "null"},\"respotted\":${stroke.respotted ?: "null"},\"scratch\":${stroke.scratch}},")
            append("\"after\":${tableJson(after)}}")
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val out = StringBuilder("{\n")

        // Random.
        out.append("\"random\":[")
        out.append(listOf(0L, 1L, 42L, -7L, Long.MAX_VALUE, 123456789L).joinToString(",") { seed ->
            val r = PoolRandom(seed)
            val next = (0 until 6).map { "\"" + java.lang.Long.toHexString(r.next()) + "\"" }
            val unit = (0 until 4).map { b(r.unit()) }
            val normal = (0 until 4).map { b(r.normal()) }
            val below = (0 until 8).map { r.nextBelow(13) }
            val shuf = r.shuffled((0..14).toList())
            "{\"seed\":$seed,\"next\":${next.joinToString(",", "[", "]")},\"unit\":${unit.joinToString(",", "[", "]")},\"normal\":${normal.joinToString(",", "[", "]")},\"below\":${ints(below)},\"shuffled\":${ints(shuf)}}"
        })
        out.append("],\n")

        // Orientations.
        out.append("\"quatStart\":[")
        out.append((0..15).joinToString(",") { n -> val q = PoolQuat.start(n); "[${b(q.x)},${b(q.y)},${b(q.z)},${b(q.w)}]" })
        out.append("],\n")
        val roll = H()
        var q = PoolQuat.start(3)
        repeat(500) { q = PoolQuat.roll(q, 0.7, -0.3); roll.d(q.x); roll.d(q.y); roll.d(q.z); roll.d(q.w) }
        out.append("\"rollHash\":\"${roll.hex()}\",\n")

        // Geometry.
        out.append("\"geometry\":[")
        out.append(listOf(PoolTableGeometry.bar, PoolTableGeometry.pro).joinToString(",") { g ->
            val cush = g.cushions.joinToString(",", "[", "]") { "[${b(it.px)},${b(it.py)},${b(it.qx)},${b(it.qy)},${it.jaw}]" }
            val pk = g.pockets.joinToString(",", "[", "]") { "[${b(it.c.x)},${b(it.c.y)},${b(it.r)},${it.corner}]" }
            val aims = g.aimPoints.joinToString(",", "[", "]") { vec(it) }
            "{\"size\":\"${g.size}\",\"cornerMouth\":${b(g.cornerMouth)},\"sideMouth\":${b(g.sideMouth)},\"cushions\":$cush,\"pockets\":$pk,\"aims\":$aims}"
        })
        out.append("],\n")

        // Racks.
        out.append("\"racks\":[")
        val racks = ArrayList<String>()
        for (size in PoolTableSize.entries) for (game in PoolVariant.entries) for (seed in 1L..40L) {
            val g = PoolTableGeometry.of(size)
            val balls = if (game == PoolVariant.EIGHT) PoolRack.eight(g, seed) else PoolRack.nine(g, seed)
            val h = H()
            for (ball in balls) { h.i(ball.n); h.d(ball.x); h.d(ball.y) }
            racks += "{\"size\":\"$size\",\"game\":\"$game\",\"seed\":$seed,\"numbers\":${ints(balls.map { it.n })},\"hash\":\"${h.hex()}\"" +
                (if (seed == 1L) ",\"positions\":${balls.joinToString(",", "[", "]") { vec(it.p) }}" else "") + "}"
        }
        out.append(racks.joinToString(",\n"))
        out.append("],\n")

        // Physics cases.
        val cases = ArrayList<String>()
        for (game in PoolVariant.entries) for (size in PoolTableSize.entries) for (seed in 1L..3L) {
            val t = PoolTableState.create(game, PoolOptions(tableSize = size), 2, 0, seed)
            val geo = t.geometry
            val cue = t.cue.p
            val straight = atan2(geo.footSpot.y - cue.y, geo.footSpot.x - cue.x)
            cases += caseJson("break-$game-$size-$seed-straight", t, PoolShot(straight, 1.0))
            cases += caseJson("break-$game-$size-$seed-spin", t, PoolShot(straight + 0.004, 0.62, Vec2(0.2, -0.3)))
            cases += caseJson("break-$game-$size-$seed-bot", t, PoolBot.plan(t, PoolDifficulty.HARD, seed * 31).shot)
            cases += caseJson("break-$game-$size-$seed-easy", t, PoolBot.plan(t, PoolDifficulty.EASY, seed * 17 + 5).shot)
        }
        for (seed in 1L..10L) {
            val t = scattered(seed, if (seed % 3 == 0L) PoolVariant.NINE else PoolVariant.EIGHT, if (seed % 4 == 0L) PoolTableSize.PRO else PoolTableSize.BAR)
            if (seed % 2 == 0L) t.ballInHand = true
            for (level in PoolDifficulty.entries) {
                cases += caseJson("scatter-$seed-$level", t, PoolBot.plan(t, level, seed * 7 + level.ordinal).shot)
            }
            cases += caseJson("scatter-$seed-manual", t, PoolShot(seed * 0.61, 0.15 + seed * 0.08, Vec2(-0.25 + seed * 0.05, 0.4 - seed * 0.07)))
        }
        out.append("\"cases\":[\n")
        out.append(cases.joinToString(",\n"))
        out.append("],\n")

        // Computer plans.
        val plans = ArrayList<String>()
        for (seed in 1L..8L) {
            val t = scattered(seed + 100, if (seed % 3 == 0L) PoolVariant.NINE else PoolVariant.EIGHT)
            if (seed % 2 == 0L) t.ballInHand = true
            val cand = PoolBot.candidates(t)
            val ch = H()
            for (c in cand) { ch.d(c.score); ch.d(c.shot.angle); ch.d(c.shot.power); ch.i(c.target); ch.i(c.pocket) }
            for (level in PoolDifficulty.entries) {
                val p = PoolBot.plan(t, level, seed * 13 + level.ordinal)
                plans += "{\"seed\":$seed,\"level\":\"$level\",\"candidates\":${cand.size},\"candidatesHash\":\"${ch.hex()}\",\"shot\":${shotJson(p.shot)},\"target\":${p.target},\"pocket\":${p.pocket},\"ghost\":${vec(p.ghost)},\"score\":${b(p.score)},\"leave\":${PoolBot.leave(t)}}"
            }
        }
        out.append("\"plans\":[\n")
        out.append(plans.joinToString(",\n"))
        out.append("],\n")

        // Aim guide.
        val guides = ArrayList<String>()
        for (seed in 1L..4L) {
            val t = scattered(seed + 200)
            val legal = t.legalFirst()
            for (k in 0 until 9) for (style in PoolAimGuide.entries) {
                val g = PoolGuide.compute(t, t.cue.p, k * 0.7, Vec2(0.0, 0.3), style, legal)
                guides += "{\"seed\":$seed,\"k\":$k,\"style\":\"$style\",\"end\":${vec(g.end)},\"ghost\":${vec(g.ghost)},\"target\":${g.target ?: "null"},\"legal\":${g.legal},\"objectEnd\":${vec(g.objectEnd)},\"cueEnd\":${vec(g.cueEnd)},\"pocket\":${g.pocket ?: "null"}}"
            }
        }
        out.append("\"guides\":[\n")
        out.append(guides.joinToString(",\n"))
        out.append("],\n")

        // Free spots.
        val spots = ArrayList<String>()
        for (seed in 1L..3L) {
            val t = scattered(seed + 300)
            t.ballInHand = true
            for (k in 0 until 6) {
                val p = t.balls[k + 1].p + Vec2(0.3 * k, -0.2 * k)
                t.kitchenOnly = k % 2 == 0
                spots += "{\"seed\":$seed,\"k\":$k,\"spot\":${vec(t.freeSpot(p))}}"
            }
        }
        out.append("\"freeSpots\":[").append(spots.joinToString(",")).append("],\n")

        // Matches.
        val m = PoolMatch.create(PoolOptions(), 2, 0, 987654321L)
        val seeds = ArrayList<String>()
        repeat(6) { m.table.winner = it % 2; m.finishRack(); m.nextRack(); seeds += "\"${m.seed}\"" }
        out.append("\"matchSeeds\":[").append(seeds.joinToString(",")).append("],\n")

        // The JVM math the engine relies on (Math == StrictMath with the sin/cos intrinsics disabled).
        val mr = java.util.Random(2024)
        val sm = ArrayList<String>()
        for (k in 0 until 3000) {
            val x = when (k % 4) { 0 -> (mr.nextDouble() * 2 - 1) * 4; 1 -> (mr.nextDouble() * 2 - 1) * 40; 2 -> (mr.nextDouble() * 2 - 1) * 0.5; else -> (mr.nextDouble() * 2 - 1) * 2000 }
            val y = (mr.nextDouble() * 2 - 1) * 10
            val p = mr.nextDouble()
            sm += "[${b(x)},${b(y)},${b(p)},${b(kotlin.math.sin(x))},${b(kotlin.math.cos(x))},${b(kotlin.math.atan2(y, x))},${b(kotlin.math.acos(p * 2 - 1))},${b(kotlin.math.ln(p + 1e-12))},${b(Math.pow(p, 1.6))},${b(Math.pow(p * 3, 1 / 1.6))}]"
        }
        out.append("\"strictMath\":[").append(sm.joinToString(",")).append("],\n")

        // Estimated minutes.
        val mins = ArrayList<Int>()
        for (seats in 2..4) for (people in 1..seats) for (len in PoolMatchLength.entries) for (fast in listOf(false, true)) {
            mins += PoolStore.estimatedMinutes(seats, people, PoolOptions(length = len, fastBots = fast))
        }
        out.append("\"minutes\":${ints(mins)}\n")
        out.append("}\n")

        val dir = System.getenv("GOLDEN_OUT")?.let { File(it) } ?: File("build")
        dir.mkdirs()
        File(dir, "pool_golden.json").writeText(out.toString())
    }
}
