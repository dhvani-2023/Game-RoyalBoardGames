import SwiftUI
import GameKit

// MARK: - Practice board rules

/// Carrom's practice board: one player at the bottom, no turns, fouls or score, unlimited shots and a re-rack
/// button. Pocketed coins (the Queen too) stay down; a pocketed striker simply comes back for the next shot.
enum CarromPractice {
    /// The setup's mode and looks, for one person at the bottom, with the clock, ICF rules and board turning off.
    static func config(_ seat: CarromSeat, _ options: CarromOptions, _ boardID: Int, _ coinsID: Int, _ strikerID: Int) -> CarromConfig {
        var o = options
        o.length = .ONE
        o.tournament = false
        o.shotClock = 0
        o.turnBoard = false
        o.freestyleTeams = false
        var s = seat
        s.side = 0
        s.isBot = false
        return CarromConfig([s], o, boardID, coinsID, strikerID, practice: true)
    }

    /// Coins still on the board.
    static func left(_ t: CarromTable) -> Int { t.coins.reduce(0) { $0 + ($1.live ? 1 : 0) } }

    /// Applies a finished physics run: coins stay where they stopped, the shooter always shoots again.
    @discardableResult
    static func apply(_ t: CarromTable, _ discs: [CarromDisc], _ run: CarromPhysics.Run, _ striker: Int) -> CarromStroke {
        let s = CarromStroke()
        s.seat = t.turn
        s.pocketed = run.pocketed.filter { $0.disc != striker }.map { discs[$0.disc].kind }
        var next = [CarromDisc]()
        next.reserveCapacity(t.coins.count)
        for i in 0..<t.coins.count {
            var c = discs[i]
            c.vx = 0.0
            c.vy = 0.0
            next.append(c)
        }
        t.coins = next
        t.strokes += 1
        t.broken = true
        if t.turn < t.stats.count {
            t.stats[t.turn].strokes += 1
            t.stats[t.turn].coins += s.pocketed.count
            t.stats[t.turn].bestCombo = Swift.max(t.stats[t.turn].bestCombo, s.pocketed.count)
        }
        s.continues = true
        return s
    }

    /// A fresh rack of the same mode.
    static func rack(_ m: CarromMatch) -> CarromTable {
        let t = CarromTable.create(m.mode, m.sides, teams: false, tournament: false, breaker: 0)
        t.practice = true
        return t
    }

    /// The hint line on the practice board (nil: the usual text).
    @MainActor
    static func hint(_ session: CarromSession) -> String? {
        let t = session.table
        if session.blocked || session.phase == .AIMING { return nil }
        if left(t) == 0 { return "Board cleared! Tap Re-rack for a fresh board" }
        if !t.broken { return "Practice · break when you're ready" }
        return "Practice · slide to place, pull back to aim"
    }
}

// MARK: - Instant replay

extension CarromSession {
    /// The Replay button shows once a shot has been played and the board is at rest.
    var canReplay: Bool {
        ExtrasFeatures.instantReplay && lastShot != nil && replay == nil && phase == .READY && !paused
    }

    /// Plays the last shot again from its recorded frames at 0.4×, with its clacks and drops.
    func startReplay() {
        guard canReplay, let last = lastShot else { return }
        let rate = ExtrasReplay.RATE
        let start = carromNow() + 0.05
        let pb = CarromPlayback(start, last.frames, last.kinds, last.live, last.pocketed, last.duration, rate: rate)
        replay = pb
        mark(pb.end)
        Haptics.play(.Light)
        let events = lastShotEvents
        let striker = lastShotStriker
        Task { @MainActor [weak self] in
            for event in events {
                let wait = start + event.time / rate - carromNow()
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard let self, self.replay === pb else { return }
                switch event.kind {
                case .HIT:
                    let level = event.strength > 1600 ? 3 : (event.strength > 700 ? 2 : (event.strength > 180 ? 1 : 0))
                    let isStriker = event.disc == striker || event.other == striker
                    CarromSound.play(isStriker ? .Strike(level) : .Clack(level), throttle: 0.015)
                case .FRAME:
                    if event.strength > 25 {
                        CarromSound.play(.Frame(event.strength > 160 ? 2 : (event.strength > 70 ? 1 : 0)), throttle: 0.04)
                    }
                case .POCKET:
                    CarromSound.play(.Pocket, throttle: 0.05)
                    Haptics.play(.Light)
                }
            }
            let rest = pb.end - carromNow()
            if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
            guard let self, self.replay === pb else { return }
            self.replay = nil
        }
    }

    /// Tap during a replay: back to the board straight away.
    func skipReplay() {
        if replay == nil { return }
        replay = nil
        mark(carromNow() + 0.05)
        Haptics.play(.Tick)
        CarromSound.play(.Tap)
    }
}

// MARK: - Practice header

/// Replaces the players header on the practice board.
struct ExtrasCarromPracticeBar: View {
    let session: CarromSession

    var body: some View {
        let t = session.table
        let seat = session.config.seats[0]
        let left = CarromPractice.left(t)
        ExtrasPracticeStrip(
            avatar: seat.player.avatar,
            name: "\(seat.player.name) · \(session.match.mode.title)",
            stats: "\(t.strokes) shot\(t.strokes == 1 ? "" : "s") · \(left) coin\(left == 1 ? "" : "s") left",
            rerackTitle: "Re-rack",
            canRerack: session.phase == .READY && session.replay == nil,
            onRerack: { session.rerack() }
        )
    }
}
