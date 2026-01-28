import Foundation

struct MoveOutcome {
    let board: [Int]
    let score: Int
    let mergedIndices: Set<Int>
    let movements: [Movement]
    let changed: Bool
}

struct GameLogic {
    static let size = 4
    static let boardCount = 16

    static func emptyIndices(board: [Int]) -> [Int] {
        board.indices.filter { board[$0] == 0 }
    }

    static func canMove(board: [Int]) -> Bool {
        if board.contains(0) { return true }
        for r in 0..<size {
            for c in 0..<size {
                let idx = r * size + c
                let v = board[idx]
                if c + 1 < size, board[idx + 1] == v { return true }
                if r + 1 < size, board[idx + size] == v { return true }
            }
        }
        return false
    }

    static func addRandomTile(board: inout [Int]) -> Int? {
        let empties = emptyIndices(board: board)
        guard !empties.isEmpty else { return nil }
        let idx = empties.randomElement()!
        let value = Double.random(in: 0..<1) < 0.9 ? 2 : 4
        board[idx] = value
        return idx
    }

    static func move(board: [Int], direction: Direction) -> MoveOutcome {
        var newBoard = board
        var totalScore = 0
        var merged = Set<Int>()
        var changed = false
        var movements: [Movement] = []
        for line in 0..<size {
            let indices = lineIndices(direction: direction, line: line)
            let values = indices.map { board[$0] }
            let (newLine, score, mergedPositions, lineMoves) = slideAndMerge(values, indices: indices)
            totalScore += score
            for (offset, idx) in indices.enumerated() {
                if newBoard[idx] != newLine[offset] { changed = true }
                newBoard[idx] = newLine[offset]
            }
            for pos in mergedPositions {
                let idx = indices[pos]
                merged.insert(idx)
            }
            movements.append(contentsOf: lineMoves)
        }

        return MoveOutcome(board: newBoard, score: totalScore, mergedIndices: merged, movements: movements, changed: changed)
    }

    private static func lineIndices(direction: Direction, line: Int) -> [Int] {
        switch direction {
        case .left:
            return (0..<size).map { line * size + $0 }
        case .right:
            return (0..<size).map { line * size + (size - 1 - $0) }
        case .up:
            return (0..<size).map { $0 * size + line }
        case .down:
            return (0..<size).map { (size - 1 - $0) * size + line }
        }
    }

    private static func slideAndMerge(_ values: [Int], indices: [Int]) -> ([Int], Int, [Int], [Movement]) {
        let tiles = values.enumerated().compactMap { offset, value -> (index: Int, value: Int)? in
            value == 0 ? nil : (indices[offset], value)
        }
        var result: [Int] = []
        var score = 0
        var mergedPositions: [Int] = []
        var lineMoves: [Movement] = []
        var i = 0
        while i < tiles.count {
            if i + 1 < tiles.count, tiles[i].value == tiles[i + 1].value {
                let mergedValue = tiles[i].value * 2
                result.append(mergedValue)
                score += mergedValue
                let destPos = result.count - 1
                mergedPositions.append(destPos)
                let destIndex = indices[destPos]
                lineMoves.append(Movement(from: tiles[i].index, to: destIndex, value: tiles[i].value, isMerge: true))
                lineMoves.append(Movement(from: tiles[i + 1].index, to: destIndex, value: tiles[i + 1].value, isMerge: true))
                i += 2
            } else {
                result.append(tiles[i].value)
                let destPos = result.count - 1
                let destIndex = indices[destPos]
                lineMoves.append(Movement(from: tiles[i].index, to: destIndex, value: tiles[i].value, isMerge: false))
                i += 1
            }
        }
        while result.count < size { result.append(0) }
        return (result, score, mergedPositions, lineMoves)
    }
}
