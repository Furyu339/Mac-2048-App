import Foundation

struct MoveOutcome {
    let board: [Int]
    let score: Int
    let mergedIndices: Set<Int>
    let movements: [Movement]
    let changed: Bool
}

struct MatchResolveOutcome {
    let board: [Int]
    let score: Int
    let upgradedIndices: Set<Int>
    let chainCount: Int
    let clearedCount: Int
}

struct GameLogic {
    static let size = 4
    static let boardCount = 16

    // 权重刷块：难度由低值主导，少量高值制造变化。
    private static let spawnWeights: [(threshold: Int, value: Int)] = [
        (55, 2),  // 0...54
        (80, 4),  // 55...79
        (95, 8),  // 80...94
        (100, 16) // 95...99
    ]

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
        addRandomTiles(board: &board, count: 1).first
    }

    static func addRandomTiles(board: inout [Int], count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var spawnedIndices: [Int] = []
        for _ in 0..<count {
            let empties = emptyIndices(board: board)
            guard !empties.isEmpty else { break }
            let idx = empties.randomElement()!
            board[idx] = randomSpawnValue()
            spawnedIndices.append(idx)
        }
        return spawnedIndices
    }

    static func maxTile(board: [Int]) -> Int {
        board.max() ?? 0
    }

    static func resolveMatchesAndCollapse(board: [Int]) -> MatchResolveOutcome {
        var working = board
        var totalScore = 0
        var chainCount = 0
        var clearedCount = 0
        var upgradedIndices: Set<Int> = []

        while true {
            let groups = matchGroups(board: working)
            if groups.isEmpty { break }
            chainCount += 1

            var clearSet: Set<Int> = []
            var upgrades: [Int: Int] = [:]
            var stepUpgraded: Set<Int> = []

            for group in groups {
                let core = coreIndex(in: group)
                let baseValue = working[core]
                guard baseValue > 0 else { continue }
                upgrades[core] = max(upgrades[core] ?? 0, baseValue * 2)
                stepUpgraded.insert(core)
                for idx in group where idx != core {
                    clearSet.insert(idx)
                }

                totalScore += baseValue * group.count
                clearedCount += max(0, group.count - 1)
            }

            for idx in clearSet {
                working[idx] = 0
            }
            for (idx, value) in upgrades {
                working[idx] = value
            }

            working = collapseDown(board: working)
            upgradedIndices = stepUpgraded
        }

        return MatchResolveOutcome(
            board: working,
            score: totalScore,
            upgradedIndices: upgradedIndices,
            chainCount: chainCount,
            clearedCount: clearedCount
        )
    }

    private static func randomSpawnValue() -> Int {
        let roll = Int.random(in: 0..<100)
        for entry in spawnWeights where roll < entry.threshold {
            return entry.value
        }
        return 2
    }

    private static func matchGroups(board: [Int]) -> [[Int]] {
        var visited: Set<Int> = []
        var groups: [[Int]] = []

        for idx in board.indices {
            let value = board[idx]
            if value == 0 || visited.contains(idx) { continue }

            var queue: [Int] = [idx]
            visited.insert(idx)
            var component: [Int] = []

            while let current = queue.popLast() {
                component.append(current)
                for next in neighbors(of: current) {
                    if visited.contains(next) { continue }
                    if board[next] != value { continue }
                    visited.insert(next)
                    queue.append(next)
                }
            }

            if component.count >= 3 {
                groups.append(component)
            }
        }

        return groups
    }

    private static func coreIndex(in group: [Int]) -> Int {
        let center = Double(size - 1) / 2.0
        return group.min { lhs, rhs in
            let ld = distanceToCenter(index: lhs, center: center)
            let rd = distanceToCenter(index: rhs, center: center)
            if ld == rd { return lhs < rhs }
            return ld < rd
        } ?? group[0]
    }

    private static func distanceToCenter(index: Int, center: Double) -> Double {
        let row = index / size
        let col = index % size
        return abs(Double(row) - center) + abs(Double(col) - center)
    }

    private static func neighbors(of index: Int) -> [Int] {
        let row = index / size
        let col = index % size
        var result: [Int] = []
        if row > 0 { result.append((row - 1) * size + col) }
        if row + 1 < size { result.append((row + 1) * size + col) }
        if col > 0 { result.append(row * size + col - 1) }
        if col + 1 < size { result.append(row * size + col + 1) }
        return result
    }

    private static func collapseDown(board: [Int]) -> [Int] {
        var collapsed = Array(repeating: 0, count: boardCount)
        for col in 0..<size {
            var writeRow = size - 1
            for row in stride(from: size - 1, through: 0, by: -1) {
                let idx = row * size + col
                let value = board[idx]
                if value == 0 { continue }
                collapsed[writeRow * size + col] = value
                writeRow -= 1
            }
        }
        return collapsed
    }

    static func createInitialBoard(seedCount: Int = 2) -> [Int] {
        var board = Array(repeating: 0, count: boardCount)
        _ = addRandomTiles(board: &board, count: max(1, seedCount))
        return board
    }

    static func isGameOver(board: [Int]) -> Bool {
        !canMove(board: board)
    }

    static func nextTurn(board: [Int], direction: Direction) -> (MoveOutcome, MatchResolveOutcome, [Int], [Int])? {
        let moveOutcome = move(board: board, direction: direction)
        if !moveOutcome.changed { return nil }

        let resolved = resolveMatchesAndCollapse(board: moveOutcome.board)
        var finalBoard = resolved.board
        let spawned = addRandomTiles(board: &finalBoard, count: 2)
        return (moveOutcome, resolved, spawned, finalBoard)
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
