import Foundation

final class EngineStressController {
    private var task: Task<Void, Never>?
    private let stressClient = EngineClient()

    func start(boardProvider: @escaping () -> [Int]) {
        task?.cancel()
        task = Task.detached(priority: .userInitiated) {
            while !Task.isCancelled {
                let base = await MainActor.run { boardProvider() }
                let batch = Self.generateBoards(base: base, count: 6, depth: 6)
                for board in batch {
                    _ = await self.stressClient.hint(board: board, score: 0, timeLimitMs: 1500, maxDepth: 9)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static func generateBoards(base: [Int], count: Int, depth: Int) -> [[Int]] {
        var result: [[Int]] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            var board = base
            for _ in 0..<depth {
                let dirs = Direction.allCases.shuffled()
                var moved = false
                for dir in dirs {
                    let outcome = GameLogic.move(board: board, direction: dir)
                    if outcome.changed {
                        board = outcome.board
                        _ = GameLogic.addRandomTile(board: &board)
                        moved = true
                        break
                    }
                }
                if !moved { break }
            }
            result.append(board)
        }
        return result
    }
}
