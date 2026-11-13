import SwiftUI
import GameKit

// MARK: - Practice table rules

/// Pool's practice table: one player, no turns, fouls or score, unlimited shots and a re-rack button.
/// The table keeps every pocketed ball down (the 8 and the 9 too); a scratch just brings the cue ball back in hand.
enum PoolPractice {
    /// The setup's table, cue and game, for one person, with the clock and pocket calls off.
    static func config(_ seat: PoolSeat, _ options: PoolOptions, _ game: PoolVariant, _ tableID: Int, _ cueID: Int) -> PoolConfig {
        var o = options
        o.game = game
        o.length = .ONE
        o.callEight = false
        o.threeFouls = false
        o.kitchenAfterScratch = false
        o.shotClock = 0
        return PoolConfig([PoolSeat(seat.player, isBot: false)], o, tableID, cueID, practice: true)
    }

    /// Any ball on the table may be hit first.
    static func legalFirst(_ t: PoolTableState) -> [Int] {
        t.balls.filter { $0.live && $0.n != 0 }.map { $0.n }
    }

    /// Object balls still on the table.
    static func left(_ t: PoolTableState) -> Int { t.balls.filter { $0.live && $0.n != 0 }.count }

    /// Applies a finished physics run: the balls stay where they stopped, the shooter always shoots again.
    static func apply(_ t: inout PoolTableState, _ after: [PoolBall], _ run: PoolPhysics.Run) -> PoolStroke {
        var s = PoolStroke()
        s.seat = t.turn
        t.balls = after.map { var b = $0; b.stop(); return b }
        t.broken = true
        t.shots += 1
        t.ballInHand = false
        t.kitchenOnly = false
        let potted = run.potted.map { after[$0.ball].n }
        s.potted = potted
        s.scratch = potted.contains(0)
        s.continues = true
        if t.turn < t.stats.count {
            t.stats[t.turn].shots += 1
            t.stats[t.turn].potted += potted.filter { $0 != 0 }.count
        }
        if s.scratch || !t.balls[0].live {
            t.balls[0] = PoolRack.cueBall(t.geometry)
            t.ballInHand = true
            t.balls[0].p = t.freeSpot(t.balls[0].p)
        }
        return s
    }

    /// A fresh rack of the same game on the same table, ball in hand behind the line for the break.
    static func rerack(_ m: PoolMatch) -> PoolMatch {
        var n = m
        n.rack += 1
        n.seed = m.seed &* 6_364_136_223_846_793_005 &+ 1
        n.table = PoolTableState.create(m.game, m.options, m.seats, 0, n.seed)
        n.table.practice = true
        return n
    }

    /// The turn line on the practice table (nil: the usual text).
    @MainActor
    static func hint(_ session: PoolSession) -> String? {
        let t = session.table
        if session.placing || session.pulling || t.ballInHand { return nil }
        if left(t) == 0 { return "Table cleared! Tap Re-rack for a fresh rack" }
        if !t.broken { return "Practice · break when you're ready" }
        return "Practice · drag to aim, pull the cue to shoot"
    }
}

// MARK: - Instant replay

extension PoolSession {
    /// The Replay button shows once a shot has been played and the table is at rest.
    var canReplay: Bool {
        ExtrasFeatures.instantReplay && lastShot != nil && replay == nil && phase == .READY && !paused
    }

    /// Plays the last shot again from its recorded frames at 0.4×, with its clicks and drops.
    func startReplay() {
        guard canReplay, let last = lastShot else { return }
        let start = poolNow() + 0.05
        let pb = PoolPlayback(
            start, last.frames, last.turns, last.numbers, last.live, last.potted, last.duration, 0.0, last.duration,
            slowRate: ExtrasReplay.RATE
        )
        replay = pb
        mark(pb.end)
        Haptics.play(.Light)
        let events = lastShotEvents
        Task { @MainActor [weak self] in
            for event in events {
                let wait = start + pb.realTime(event.time) - poolNow()
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard let self, self.replay === pb else { return }
                switch event.kind {
                case .Hit:
                    let level = event.strength > 400 ? 3 : (event.strength > 150 ? 2 : (event.strength > 40 ? 1 : 0))
                    PoolSound.play(PoolSound.click(level), 0.012)
                case .Cushion:
                    if event.strength > 15 {
                        PoolSound.play(PoolSound.cushion(event.strength > 200 ? 2 : (event.strength > 60 ? 1 : 0)), 0.04)
                    }
                case .Jaw:
                    if event.strength > 20 { PoolSound.play(PoolSound.jaw, 0.08) }
                case .Pocket:
                    PoolSound.play(PoolSound.pocket, 0.05)
                    Haptics.play(.Light)
                }
            }
            let rest = pb.end - poolNow()
            if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
            guard let self, self.replay === pb else { return }
            self.replay = nil
        }
    }

    /// Tap during a replay: back to the table straight away.
    func skipReplay() {
        if replay == nil { return }
        replay = nil
        mark(poolNow() + 0.05)
        Haptics.play(.Tick)
        PoolSound.play(PoolSound.tap)
    }
}

// MARK: - Practice header

/// Replaces the players bar on the practice table.
struct ExtrasPoolPracticeBar: View {
    let session: PoolSession

    var body: some View {
        let t = session.table
        let seat = session.config.seats[0]
        let left = PoolPractice.left(t)
        ExtrasPracticeStrip(
            avatar: seat.player.avatar,
            name: "\(seat.player.name) · \(t.game.title)",
            stats: "\(t.shots) shot\(t.shots == 1 ? "" : "s") · \(left) ball\(left == 1 ? "" : "s") left",
            rerackTitle: "Re-rack",
            canRerack: session.phase == .READY && session.replay == nil,
            onRerack: { session.rerack() }
        )
    }
}
