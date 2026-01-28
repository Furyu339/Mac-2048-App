import Foundation

struct Heuristics {
    static func evaluate(board: [Int], score: Int) -> Double {
        let empty = Double(GameLogic.emptyIndices(board: board).count)
        let smooth = smoothness(board: board)
        let mono = monotonicity(board: board)
        let maxTile = Double(board.max() ?? 0)
        let corner = cornerMaxScore(board: board)
        let stability = stabilityPenalty(board: board)
        return empty * 130.0 + smooth * 2.5 + mono * 18.0 + log2(maxTile + 1) * 22.0 + corner * 45.0 - stability * 8.0 + Double(score) * 0.08
    }

    private static func smoothness(board: [Int]) -> Double {
        var penalty = 0.0
        for r in 0..<GameLogic.size {
            for c in 0..<GameLogic.size {
                let idx = r * GameLogic.size + c
                let v = board[idx]
                if v == 0 { continue }
                let logv = log2(Double(v))
                if c + 1 < GameLogic.size {
                    let nv = board[idx + 1]
                    if nv > 0 { penalty -= abs(logv - log2(Double(nv))) }
                }
                if r + 1 < GameLogic.size {
                    let nv = board[idx + GameLogic.size]
                    if nv > 0 { penalty -= abs(logv - log2(Double(nv))) }
                }
            }
        }
        return penalty
    }

    private static func monotonicity(board: [Int]) -> Double {
        var totals = [0.0, 0.0, 0.0, 0.0]
        for r in 0..<GameLogic.size {
            var current = 0
            var next = 1
            while next < GameLogic.size {
                let curVal = board[r * GameLogic.size + current]
                let nextVal = board[r * GameLogic.size + next]
                if curVal > nextVal {
                    totals[0] += log2(Double(curVal + 1)) - log2(Double(nextVal + 1))
                } else if nextVal > curVal {
                    totals[1] += log2(Double(nextVal + 1)) - log2(Double(curVal + 1))
                }
                current = next
                next += 1
            }
        }
        for c in 0..<GameLogic.size {
            var current = 0
            var next = 1
            while next < GameLogic.size {
                let curVal = board[current * GameLogic.size + c]
                let nextVal = board[next * GameLogic.size + c]
                if curVal > nextVal {
                    totals[2] += log2(Double(curVal + 1)) - log2(Double(nextVal + 1))
                } else if nextVal > curVal {
                    totals[3] += log2(Double(nextVal + 1)) - log2(Double(curVal + 1))
                }
                current = next
                next += 1
            }
        }
        return max(totals[0], totals[1]) + max(totals[2], totals[3])
    }

    private static func cornerMaxScore(board: [Int]) -> Double {
        guard let maxVal = board.max(), maxVal > 0 else { return 0 }
        let corners = [0, GameLogic.size - 1, GameLogic.boardCount - GameLogic.size, GameLogic.boardCount - 1]
        return corners.contains(where: { board[$0] == maxVal }) ? 1.0 : -1.0
    }

    private static func stabilityPenalty(board: [Int]) -> Double {
        var penalty = 0.0
        for r in 0..<GameLogic.size {
            for c in 0..<GameLogic.size {
                let idx = r * GameLogic.size + c
                let v = board[idx]
                if v == 0 { continue }
                if c + 1 < GameLogic.size {
                    let nv = board[idx + 1]
                    if nv > 0 { penalty += abs(log2(Double(v)) - log2(Double(nv))) }
                }
                if r + 1 < GameLogic.size {
                    let nv = board[idx + GameLogic.size]
                    if nv > 0 { penalty += abs(log2(Double(v)) - log2(Double(nv))) }
                }
            }
        }
        return penalty
    }
}
