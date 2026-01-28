import Foundation

enum GPUSelfGenerator {
    static func generateBoards(batch: Int, depth: Int) -> [Int32] {
        var result: [Int32] = []
        result.reserveCapacity(batch * 16)
        for _ in 0..<batch {
            var board = Array(repeating: 0, count: 16)
            _ = GameLogic.addRandomTile(board: &board)
            _ = GameLogic.addRandomTile(board: &board)
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
            for i in 0..<16 { result.append(Int32(board[i])) }
        }
        return result
    }
}
