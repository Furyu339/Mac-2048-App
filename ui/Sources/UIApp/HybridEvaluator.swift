import Foundation

final class HybridEvaluator {
    private let gpu = GPUEvaluator()

    func gpuDirectionScores(board: [Int], batchPerDir: Int, rolloutDepth: Int) -> [Direction: Float] {
        guard let gpu else {
            return Direction.allCases.reduce(into: [:]) { $0[$1] = -Float.greatestFiniteMagnitude }
        }

        var ranges: [Direction: Range<Int>] = [:]
        var flatBoards: [Int32] = []
        flatBoards.reserveCapacity(batchPerDir * 16 * Direction.allCases.count)

        var index = 0
        for dir in Direction.allCases {
            let outcome = GameLogic.move(board: board, direction: dir)
            if !outcome.changed {
                ranges[dir] = index..<index
                continue
            }
            for _ in 0..<batchPerDir {
                var b = outcome.board
                for _ in 0..<rolloutDepth {
                    let shuffled = Direction.allCases.shuffled()
                    var moved = false
                    for d in shuffled {
                        let o = GameLogic.move(board: b, direction: d)
                        if o.changed {
                            b = o.board
                            _ = GameLogic.addRandomTile(board: &b)
                            moved = true
                            break
                        }
                    }
                    if !moved { break }
                }
                for i in 0..<16 { flatBoards.append(Int32(b[i])) }
            }
            let start = index
            index += batchPerDir
            ranges[dir] = start..<index
        }

        if index == 0 { return [:] }
        let scores = gpu.evaluate(boards: flatBoards, boardCount: index, iterations: 32768)
        var result: [Direction: Float] = [:]
        for dir in Direction.allCases {
            guard let range = ranges[dir], !range.isEmpty else {
                result[dir] = -Float.greatestFiniteMagnitude
                continue
            }
            var total: Float = 0
            for i in range { total += scores[i] }
            result[dir] = total / Float(range.count)
        }
        return result
    }

    func combine(cpuDirection: Direction?, cpuValue: Double, gpuScores: [Direction: Float]) -> Direction? {
        let bestGpu = gpuScores.max(by: { $0.value < $1.value })?.key
        guard let bestGpu else { return cpuDirection }

        var best = bestGpu
        var bestScore = gpuScores[bestGpu] ?? -Float.greatestFiniteMagnitude

        if let cpuDirection {
            let bonus = max(1.0, abs(cpuValue)) * 0.15
            let cpuScore = (gpuScores[cpuDirection] ?? -Float.greatestFiniteMagnitude) + Float(bonus)
            if cpuScore > bestScore {
                best = cpuDirection
                bestScore = cpuScore
            }
        }

        return best
    }
}
