import Foundation

final class ExpectimaxAI {
    private var cache: [UInt64: Double] = [:]
    private let cacheLock = NSLock()
    private let maxCacheSize = 200_000
    private let parallelChanceThreshold = 6
    private let metricsLock = NSLock()
    private var nodesEvaluated = 0
    private var cacheHits = 0
    private var deadlineHits = 0

    func bestMove(board: [Int], score: Int, timeLimit: TimeInterval = 0.03, maxDepth: Int = 4) -> Direction? {
        cacheLock.lock()
        cache.removeAll(keepingCapacity: true)
        cacheLock.unlock()
        resetMetrics()
        let deadline = CFAbsoluteTimeGetCurrent() + timeLimit
        let start = CFAbsoluteTimeGetCurrent()
        AILogger.shared.append("AI 开始: 深度 \(maxDepth), 时间上限 \(String(format: "%.2f", timeLimit))s")

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let snapshot = self.metricsSnapshot()
            AILogger.shared.append("AI 运行中: \(String(format: "%.2f", elapsed))s, 节点 \(snapshot.nodes), 缓存命中 \(snapshot.hits), 超时 \(snapshot.deadlines)")
        }
        timer.resume()
        defer { timer.cancel() }

        var candidates: [(Direction, MoveOutcome)] = []
        candidates.reserveCapacity(Direction.allCases.count)
        for dir in Direction.allCases {
            let outcome = GameLogic.move(board: board, direction: dir)
            guard outcome.changed else { continue }
            candidates.append((dir, outcome))
        }
        guard !candidates.isEmpty else {
            AILogger.shared.append("AI 结束: 无可行动作")
            return nil
        }

        var values = Array(repeating: -Double.infinity, count: candidates.count)
        DispatchQueue.concurrentPerform(iterations: candidates.count) { i in
            let (dir, outcome) = candidates[i]
            let value = self.expectimax(board: outcome.board, score: score + outcome.score, depth: maxDepth - 1, isPlayer: false, deadline: deadline)
            values[i] = value
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let snapshot = self.metricsSnapshot()
            AILogger.shared.append("方向 \(dir.label) 完成: 值 \(String(format: "%.2f", value)), \(String(format: "%.2f", elapsed))s, 节点 \(snapshot.nodes)")
        }

        var bestIndex = 0
        for i in 1..<values.count {
            if values[i] > values[bestIndex] { bestIndex = i }
        }
        let bestDir = candidates[bestIndex].0
        let endElapsed = CFAbsoluteTimeGetCurrent() - start
        let snapshot = metricsSnapshot()
        AILogger.shared.append("AI 结束: 最优 \(bestDir.label), \(String(format: "%.2f", endElapsed))s, 节点 \(snapshot.nodes), 缓存命中 \(snapshot.hits), 超时 \(snapshot.deadlines)")
        return bestDir
    }

    private func expectimax(board: [Int], score: Int, depth: Int, isPlayer: Bool, deadline: CFAbsoluteTime) -> Double {
        bumpNodes()
        if CFAbsoluteTimeGetCurrent() > deadline {
            bumpDeadline()
            return Heuristics.evaluate(board: board, score: score)
        }
        if depth == 0 || !GameLogic.canMove(board: board) {
            return Heuristics.evaluate(board: board, score: score)
        }

        let key = BoardHash.hash(board: board, depth: depth, isPlayer: isPlayer)
        if let cached = cachedValue(for: key) {
            bumpCacheHit()
            return cached
        }

        let value: Double
        if isPlayer {
            var best = -Double.infinity
            for dir in Direction.allCases {
                let outcome = GameLogic.move(board: board, direction: dir)
                guard outcome.changed else { continue }
                let v = expectimax(board: outcome.board, score: score + outcome.score, depth: depth - 1, isPlayer: false, deadline: deadline)
                if v > best { best = v }
            }
            if best == -Double.infinity {
                best = Heuristics.evaluate(board: board, score: score)
            }
            value = best
        } else {
            let empties = GameLogic.emptyIndices(board: board)
            if empties.isEmpty {
                value = Heuristics.evaluate(board: board, score: score)
            } else {
                let prob2 = 0.9 / Double(empties.count)
                let prob4 = 0.1 / Double(empties.count)
                if depth > 1, empties.count >= parallelChanceThreshold {
                    var partials = Array(repeating: 0.0, count: empties.count)
                    DispatchQueue.concurrentPerform(iterations: empties.count) { i in
                        let idx = empties[i]
                        var local = 0.0
                        var b2 = board
                        b2[idx] = 2
                        local += prob2 * self.expectimax(board: b2, score: score, depth: depth - 1, isPlayer: true, deadline: deadline)

                        var b4 = board
                        b4[idx] = 4
                        local += prob4 * self.expectimax(board: b4, score: score, depth: depth - 1, isPlayer: true, deadline: deadline)
                        partials[i] = local
                    }
                    value = partials.reduce(0.0, +)
                } else {
                    var total = 0.0
                    for idx in empties {
                        var b2 = board
                        b2[idx] = 2
                        total += prob2 * expectimax(board: b2, score: score, depth: depth - 1, isPlayer: true, deadline: deadline)

                        var b4 = board
                        b4[idx] = 4
                        total += prob4 * expectimax(board: b4, score: score, depth: depth - 1, isPlayer: true, deadline: deadline)
                    }
                    value = total
                }
            }
        }

        cacheLock.lock()
        if cache.count > maxCacheSize { cache.removeAll(keepingCapacity: true) }
        cache[key] = value
        cacheLock.unlock()
        return value
    }

    private func cachedValue(for key: UInt64) -> Double? {
        cacheLock.lock()
        let value = cache[key]
        cacheLock.unlock()
        return value
    }

    private func resetMetrics() {
        metricsLock.lock()
        nodesEvaluated = 0
        cacheHits = 0
        deadlineHits = 0
        metricsLock.unlock()
    }

    private func bumpNodes() {
        metricsLock.lock()
        nodesEvaluated += 1
        metricsLock.unlock()
    }

    private func bumpCacheHit() {
        metricsLock.lock()
        cacheHits += 1
        metricsLock.unlock()
    }

    private func bumpDeadline() {
        metricsLock.lock()
        deadlineHits += 1
        metricsLock.unlock()
    }

    private func metricsSnapshot() -> (nodes: Int, hits: Int, deadlines: Int) {
        metricsLock.lock()
        let snapshot = (nodesEvaluated, cacheHits, deadlineHits)
        metricsLock.unlock()
        return snapshot
    }
}
