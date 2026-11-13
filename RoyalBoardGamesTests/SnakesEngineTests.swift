import XCTest
@testable import RoyalBoardGames

/// 1:1 port of app/src/test/.../snakes/SnakesEngineTest.kt.
final class SnakesEngineTests: XCTestCase {
    private let plain = SnakesRules(requireSixToStart: false, exactRollToFinish: true, extraTurnOnSix: false)

    func testBoardSnakesBetweenRows() {
        XCTAssertTrue(SnakesBoard.cell(1) == (9, 0))
        XCTAssertTrue(SnakesBoard.cell(10) == (9, 9))
        XCTAssertTrue(SnakesBoard.cell(11) == (8, 9))
        XCTAssertTrue(SnakesBoard.cell(20) == (8, 0))
        XCTAssertTrue(SnakesBoard.cell(91) == (0, 9))
        XCTAssertTrue(SnakesBoard.cell(100) == (0, 0))
        for square in 1...100 {
            let (row, col) = SnakesBoard.cell(square)
            XCTAssertEqual(square, SnakesBoard.square(row, col))
        }
    }

    func testSnakesGoDownLaddersGoUp() {
        for (bottom, top) in SnakesBoard.ladderPairs { XCTAssertTrue(top > bottom) }
        for (head, tail) in SnakesBoard.snakePairs { XCTAssertTrue(tail < head) }
        XCTAssertTrue(Set(SnakesBoard.ladders.keys).intersection(SnakesBoard.snakes.keys).isEmpty)
    }

    func testPlayerCountIsTwoToSix() {
        for count in 2...6 { XCTAssertEqual(count, SnakesMatch(count, plain).positions.count) }
    }

    func testStepsSquareBySquare() {
        let game = SnakesMatch(2, plain)
        let first = game.roll(3)
        XCTAssertTrue(first.from == 0 && first.to == 3)
        XCTAssertEqual([1, 2, 3], first.steps)
        XCTAssertNil(first.jump)
        XCTAssertEqual(SnakesMove.Outcome.Moved, first.outcome)
        XCTAssertEqual(1, first.nextPlayer)
    }

    func testLadderAndSnake() {
        let game = SnakesMatch(2, plain, [3, 38])
        let climb = game.roll(4)
        XCTAssertEqual(SnakesMove.Jump.Ladder(from: 7, to: 47), climb.jump)
        XCTAssertTrue(climb.to == 47 && climb.steps.last == 7)
        let snake = game.roll(5)
        XCTAssertEqual(SnakesMove.Jump.Snake(from: 43, to: 3), snake.jump)
        XCTAssertEqual(3, game.positions[1])
        let quiet = game.roll(2)
        XCTAssertNil(quiet.jump)
        XCTAssertEqual(49, game.positions[0])
    }

    func testTurnsRotate() {
        let game = SnakesMatch(3, plain)
        var order: [Int] = []
        for _ in 0..<6 {
            order.append(game.current)
            game.roll(2)
        }
        XCTAssertEqual([0, 1, 2, 0, 1, 2], order)
    }

    func testRequireSixToStart() {
        let game = SnakesMatch(2, plain.copy(requireSixToStart: true))
        let miss = game.roll(5)
        XCTAssertTrue(miss.outcome == .NeedSix && game.positions[0] == 0 && game.current == 1)
        game.roll(3)
        let enter = game.roll(6)
        XCTAssertTrue(enter.outcome == .Moved && game.positions[0] == 6)
    }

    func testExtraTurnOnSixAndThreeSixes() {
        let game = SnakesMatch(2, plain.copy(extraTurnOnSix: true))
        let six = game.roll(6)
        XCTAssertTrue(six.extraTurn && game.current == 0)
        game.roll(6)
        XCTAssertEqual(0, game.current)
        let before = game.positions[0]
        let third = game.roll(6)
        XCTAssertEqual(SnakesMove.Outcome.ThreeSixes, third.outcome)
        XCTAssertEqual(before, game.positions[0], "third six doesn't move")
        XCTAssertEqual(1, game.current)
    }

    func testExactRollToFinish() {
        let game = SnakesMatch(2, plain, [97, 10])
        let over = game.roll(5)
        XCTAssertEqual(SnakesMove.Outcome.Overshoot(needed: 3), over.outcome)
        XCTAssertEqual(97, game.positions[0])
        game.roll(1)
        let exact = game.roll(3)
        XCTAssertEqual(SnakesMove.Outcome.Finished(place: 1), exact.outcome)
        XCTAssertTrue(game.isOver, "two-player game ends at the first finisher")
    }

    func testOvershootFinishesWithoutExactRule() {
        let game = SnakesMatch(2, plain.copy(exactRollToFinish: false), [97, 10])
        let move = game.roll(6)
        XCTAssertEqual(100, move.to)
        XCTAssertEqual([0, 1], game.finishOrder)
    }

    func testSnakeGuardsTheLastRow() {
        let game = SnakesMatch(2, plain, [94, 10])
        let move = game.roll(5)
        XCTAssertEqual(SnakesMove.Jump.Snake(from: 99, to: 80), move.jump)
        XCTAssertEqual(SnakesMove.Outcome.Moved, move.outcome)
        XCTAssertEqual(80, game.positions[0])
    }

    func testSnakeBodiesEndOnTheirSquares() {
        for (head, tail) in SnakesBoard.snakePairs {
            let start = SnakesGeometry.snakePoint(head, 0.0)
            let end = SnakesGeometry.snakePoint(head, 1.0)
            let a = SnakesGeometry.center(head)
            let b = SnakesGeometry.center(tail)
            XCTAssertTrue(abs(start.x - a.x) < 0.001 && abs(start.y - a.y) < 0.001, "snake \(head) starts on its head square")
            XCTAssertTrue(abs(end.x - b.x) < 0.001 && abs(end.y - b.y) < 0.001, "snake \(head) ends on its tail square")
        }
    }

    func testLayoutIsClean() {
        let ends = Set(SnakesBoard.ladders.keys).union(SnakesBoard.ladders.values).union(SnakesBoard.snakes.keys).union(SnakesBoard.snakes.values)
        let list = Array(SnakesBoard.ladders.keys) + Array(SnakesBoard.ladders.values) + Array(SnakesBoard.snakes.keys) + Array(SnakesBoard.snakes.values)
        XCTAssertEqual(list.count, Set(list).count, "every square holds at most one end")
        XCTAssertFalse(ends.contains(1) || ends.contains(100))
        for (bottom, top) in SnakesBoard.ladderPairs {
            let a = SnakesBoard.cell(bottom)
            let b = SnakesBoard.cell(top)
            XCTAssertTrue(a.first > b.first, "ladder \(bottom) climbs at least one row")
            XCTAssertTrue(abs(a.second - b.second) <= a.first - b.first, "ladder \(bottom) is no flatter than 45°")
        }
    }

    func testFinishingOrderWithThreePlayers() {
        let game = SnakesMatch(3, plain, [99, 99, 50])
        let first = game.roll(1)
        XCTAssertEqual(SnakesMove.Outcome.Finished(place: 1), first.outcome)
        XCTAssertFalse(game.isOver)
        XCTAssertEqual(1, game.current)
        let second = game.roll(1)
        XCTAssertEqual(SnakesMove.Outcome.Finished(place: 2), second.outcome)
        XCTAssertTrue(game.isOver)
        XCTAssertEqual([0, 1, 2], game.finishOrder)
        XCTAssertEqual([0, 1, 2], game.standings)
    }

    func testFinishedPlayersAreSkipped() {
        let game = SnakesMatch(3, plain, [99, 40, 50])
        game.roll(1)
        XCTAssertEqual(1, game.current)
        game.roll(2)
        XCTAssertEqual(2, game.current)
        game.roll(2)
        XCTAssertEqual(1, game.current, "player 1 is skipped after finishing")
    }

    func testRestoredMatchKeepsState() {
        let game = SnakesMatch(3, plain, [99, 40, 50])
        game.roll(1)
        let copy = SnakesMatch(3, plain, game.positions, game.current, game.finishOrder, game.sixStreak, game.turnCount)
        XCTAssertEqual(game.positions, copy.positions)
        XCTAssertEqual(game.finishOrder, copy.finishOrder)
        XCTAssertEqual(game.current, copy.current)
        XCTAssertEqual(game.standings, copy.standings)
    }

    func testSeededRandomIsDeterministic() {
        let a = SeededRandom(7)
        let b = SeededRandom(7)
        for _ in 0..<20 {
            let v = a.next()
            XCTAssertEqual(v, b.next(), accuracy: 0.0)
            XCTAssertTrue((0.0...1.0).contains(v))
        }
    }
}
