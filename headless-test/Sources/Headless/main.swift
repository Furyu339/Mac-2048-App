import Foundation
import Metal

// MARK: - Models

enum Direction: String, CaseIterable, Codable {
    case up, down, left, right
}

struct Movement: Codable {
    let from: Int
    let to: Int
    let value: Int
    let isMerge: Bool

    enum CodingKeys: String, CodingKey {
        case from, to, value
        case isMerge = "is_merge"
    }
}

struct EngineStateResponse: Codable {
    let id: UInt64
    let type: String
    let board: [Int]
    let score: Int
    let best_score: Int
    let is_game_over: Bool
}

struct EngineHintResponse: Codable {
    let id: UInt64
    let type: String
    let direction: Direction?
    let value: Double
}

struct EngineMoveResultResponse: Codable {
    let id: UInt64
    let type: String
    let previous_board: [Int]
    let final_board: [Int]
    let movements: [Movement]
    let merged_indices: [Int]
    let spawned_index: Int?
    let score: Int
    let best_score: Int
    let is_game_over: Bool
    let move_duration_ms: UInt64
    let merge_duration_ms: UInt64
}

// MARK: - GameLogic (same as UI)

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

    static func move(board: [Int], direction: Direction) -> ([Int], Bool) {
        var newBoard = board
        var changed = false
        for line in 0..<size {
            let indices = lineIndices(direction: direction, line: line)
            let values = indices.map { board[$0] }
            let (newLine, _, _, _) = slideAndMerge(values, indices: indices)
            for (offset, idx) in indices.enumerated() {
                if newBoard[idx] != newLine[offset] { changed = true }
                newBoard[idx] = newLine[offset]
            }
        }
        return (newBoard, changed)
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

// MARK: - GPU Evaluator (same logic as UI)

final class GPUEvaluator {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let function = library.makeFunction(name: "evaluate_boards") else { return nil }
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            return nil
        }
    }

    func evaluate(boards: [Int32], boardCount: Int, iterations: UInt32) -> [Float] {
        let totalInts = boardCount * 16
        if boards.count < totalInts { return [] }
        guard let commandBuffer = queue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return [] }

        let inputSize = totalInts * MemoryLayout<Int32>.stride
        let outputSize = boardCount * MemoryLayout<Float>.stride
        guard let inBuffer = device.makeBuffer(bytes: boards, length: inputSize, options: []),
              let outBuffer = device.makeBuffer(length: outputSize, options: []) else { return [] }

        commandEncoder.setComputePipelineState(pipeline)
        commandEncoder.setBuffer(inBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(outBuffer, offset: 0, index: 1)
        var count = UInt32(boardCount)
        commandEncoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 2)
        var iters = iterations
        commandEncoder.setBytes(&iters, length: MemoryLayout<UInt32>.stride, index: 3)

        let width = max(1, pipeline.threadExecutionWidth)
        let threadsPerThreadgroup = MTLSize(width: width, height: 1, depth: 1)
        let threads = MTLSize(width: boardCount, height: 1, depth: 1)
        commandEncoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let outPtr = outBuffer.contents().bindMemory(to: Float.self, capacity: boardCount)
        return Array(UnsafeBufferPointer(start: outPtr, count: boardCount))
    }

    private static let shaderSource = """
#include <metal_stdlib>
using namespace metal;

kernel void evaluate_boards(const device int *boards [[buffer(0)]],
                            device float *outScores [[buffer(1)]],
                            constant uint &boardCount [[buffer(2)]],
                            constant uint &iterations [[buffer(3)]],
                            uint gid [[thread_position_in_grid]]) {
    if (gid >= boardCount) return;
    uint base = gid * 16u;

    float empty = 0.0;
    float smooth = 0.0;
    float monoRow = 0.0;
    float monoRowRev = 0.0;
    float monoCol = 0.0;
    float monoColRev = 0.0;
    int maxVal = 0;

    for (uint i = 0; i < 16; i++) {
        int v = boards[base + i];
        if (v == 0) empty += 1.0;
        if (v > maxVal) maxVal = v;
    }

    for (uint r = 0; r < 4; r++) {
        for (uint c = 0; c < 4; c++) {
            uint idx = r * 4 + c;
            int v = boards[base + idx];
            if (v == 0) continue;
            float logv = log2((float)v);
            if (c + 1 < 4) {
                int nv = boards[base + idx + 1];
                if (nv > 0) {
                    float logn = log2((float)nv);
                    smooth -= fabs(logv - logn);
                }
            }
            if (r + 1 < 4) {
                int nv = boards[base + idx + 4];
                if (nv > 0) {
                    float logn = log2((float)nv);
                    smooth -= fabs(logv - logn);
                }
            }
        }

        for (uint c = 0; c + 1 < 4; c++) {
            int cur = boards[base + r * 4 + c];
            int nxt = boards[base + r * 4 + c + 1];
            float lc = log2((float)(cur + 1));
            float ln = log2((float)(nxt + 1));
            if (cur > nxt) monoRow += lc - ln; else if (nxt > cur) monoRowRev += ln - lc;
        }
    }

    for (uint c = 0; c < 4; c++) {
        for (uint r = 0; r + 1 < 4; r++) {
            int cur = boards[base + r * 4 + c];
            int nxt = boards[base + (r + 1) * 4 + c];
            float lc = log2((float)(cur + 1));
            float ln = log2((float)(nxt + 1));
            if (cur > nxt) monoCol += lc - ln; else if (nxt > cur) monoColRev += ln - lc;
        }
    }

    float mono = max(monoRow, monoRowRev) + max(monoCol, monoColRev);
    float maxTile = log2((float)(maxVal + 1));

    int c0 = boards[base + 0];
    int c1 = boards[base + 3];
    int c2 = boards[base + 12];
    int c3 = boards[base + 15];
    float corner = (maxVal > 0 && (c0 == maxVal || c1 == maxVal || c2 == maxVal || c3 == maxVal)) ? 1.0 : -1.0;

    float score = empty * 130.0 + smooth * 2.5 + mono * 18.0 + maxTile * 22.0 + corner * 45.0;
    float acc = score;
    for (uint i = 0; i < iterations; i++) {
        acc = acc * 1.00001f + 0.0001f;
        acc = acc + sin(acc * 0.0001f);
        acc = acc + cos(acc * 0.0002f);
        acc = acc + sqrt(fabs(acc)) * 0.00001f;
        acc = acc * 0.99999f + 0.00005f;
    }
    outScores[gid] = acc;
}
"""
}

// MARK: - Hybrid

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
            let (b, changed) = GameLogic.move(board: board, direction: dir)
            if !changed {
                ranges[dir] = index..<index
                continue
            }
            for _ in 0..<batchPerDir {
                var bb = b
                for _ in 0..<rolloutDepth {
                    let shuffled = Direction.allCases.shuffled()
                    var moved = false
                    for d in shuffled {
                        let (nb, ch) = GameLogic.move(board: bb, direction: d)
                        if ch {
                            bb = nb
                            _ = GameLogic.addRandomTile(board: &bb)
                            moved = true
                            break
                        }
                    }
                    if !moved { break }
                }
                for i in 0..<16 { flatBoards.append(Int32(bb[i])) }
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

// MARK: - Engine Client

final class EngineClient {
    private let queue = DispatchQueue(label: "engine.client.queue")
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextId: UInt64 = 1
    private var pending: [UInt64: (Data) -> Void] = [:]

    func startIfNeeded() {
        if process != nil { return }
        let proc = Process()
        let path = "/Users/furyu/Desktop/2048-b-project/engine/target/release/engine"
        proc.executableURL = URL(fileURLWithPath: path)
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        do { try proc.run() } catch { return }
        process = proc
        stdinPipe = inPipe
        stdoutPipe = outPipe
        readOutput()
    }

    func reset() async -> EngineStateResponse? {
        let id = nextRequestId()
        let req: [String: Any] = ["type": "reset", "id": id]
        return await send(request: req) { data in
            try? JSONDecoder().decode(EngineStateResponse.self, from: data)
        }
    }

    func hint(board: [Int], score: Int, timeLimitMs: UInt64, maxDepth: Int) async -> EngineHintResponse? {
        let id = nextRequestId()
        let req: [String: Any] = [
            "type": "hint",
            "id": id,
            "board": board,
            "score": score,
            "time_limit_ms": timeLimitMs,
            "max_depth": maxDepth
        ]
        return await send(request: req) { data in
            try? JSONDecoder().decode(EngineHintResponse.self, from: data)
        }
    }

    func move(direction: Direction) async -> EngineMoveResultResponse? {
        let id = nextRequestId()
        let req: [String: Any] = ["type": "move", "id": id, "direction": direction.rawValue]
        return await send(request: req) { data in
            try? JSONDecoder().decode(EngineMoveResultResponse.self, from: data)
        }
    }

    private func send<T>(request: [String: Any], decode: @escaping (Data) -> T?) async -> T? {
        startIfNeeded()
        guard let stdinPipe else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        let line = data + Data([0x0A])
        let id = (request["id"] as? UInt64) ?? 0
        return await withCheckedContinuation { continuation in
            queue.async {
                self.pending[id] = { data in
                    continuation.resume(returning: decode(data))
                }
                stdinPipe.fileHandleForWriting.write(line)
            }
        }
    }

    private func readOutput() {
        guard let stdoutPipe else { return }
        let handle = stdoutPipe.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                self?.queue.async {
                    self?.processBuffer(data)
                }
            }
        }
    }

    private var buffer = Data()
    private func processBuffer(_ data: Data) {
        buffer.append(data)
        while let range = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0...range.lowerBound)
            guard !line.isEmpty else { continue }
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                let id: UInt64? = (obj["id"] as? UInt64) ?? (obj["id"] as? Int).map { UInt64($0) }
                guard let id else { continue }
                if let handler = pending.removeValue(forKey: id) {
                    handler(line)
                }
            }
        }
    }

    private func nextRequestId() -> UInt64 {
        let id = nextId
        nextId += 1
        return id
    }
}

// MARK: - GPU Workload (headless)

final class GPUWorkloadController {
    private var tasks: [Task<Void, Never>] = []

    func start(boardProvider: @escaping () -> [Int]) {
        stop()
        let configs: [(Int, Int, UInt32)] = [
            (32768, 8, 8192)
        ]

        for (batch, depth, iters) in configs {
            let t = Task.detached(priority: .userInitiated) {
                guard let evaluator = GPUEvaluator() else { return }
                while !Task.isCancelled {
                    let boards = GPUSelfGenerator.generateBoards(batch: batch, depth: depth)
                    _ = evaluator.evaluate(boards: boards, boardCount: batch, iterations: iters)
                }
            }
            tasks.append(t)
        }

    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}

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
                    let (nb, ch) = GameLogic.move(board: board, direction: dir)
                    if ch {
                        board = nb
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

    static func generateBoardsFrom(base: [Int], batch: Int, depth: Int) -> [Int32] {
        var result: [Int32] = []
        result.reserveCapacity(batch * 16)
        for _ in 0..<batch {
            var board = base
            for _ in 0..<depth {
                let dirs = Direction.allCases.shuffled()
                var moved = false
                for dir in dirs {
                    let (nb, ch) = GameLogic.move(board: board, direction: dir)
                    if ch {
                        board = nb
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

// MARK: - Runner

struct Report {
    var scores: [Int] = []
    var maxTileCounts: [Int: Int] = [:]
    var movesPerGame: [Int] = []
}

struct GameResult {
    let score: Int
    let maxTile: Int
    let moves: Int
}

actor GameAllocator {
    private var nextIndex: Int = 0
    private let total: Int

    init(total: Int) {
        self.total = total
    }

    func next() -> Int? {
        guard nextIndex < total else { return nil }
        let current = nextIndex
        nextIndex += 1
        return current
    }
}

actor ReportCollector {
    private var report = Report()

    func add(result: GameResult, index: Int, total: Int, workerId: Int) {
        report.scores.append(result.score)
        report.movesPerGame.append(result.moves)
        report.maxTileCounts[result.maxTile, default: 0] += 1
        print("[W\(workerId)] ✅ done | game \(index + 1)/\(total) | score=\(result.score) | max=\(result.maxTile) | moves=\(result.moves)")
        fflush(stdout)
    }

    func build() -> Report { report }
}

@main
struct HeadlessRunner {
    static func main() async {
        print("Headless start")
        fflush(stdout)
        let games = 4
        let runner = Runner()
        let report = await runner.run(games: games)
        runner.writeReport(report: report)
    }
}

final class Runner {
    private let gpuWorkload = GPUWorkloadController()

    func run(games: Int) async -> Report {
        let baseBoard = Array(repeating: 0, count: 16)
        gpuWorkload.start { baseBoard }

        let allocator = GameAllocator(total: games)
        let collector = ReportCollector()
        let workerCount = 4

        await withTaskGroup(of: Void.self) { group in
            for workerId in 1...workerCount {
                group.addTask {
                    let engine = EngineClient()
                    let hybrid = HybridEvaluator()
                    while let gameIndex = await allocator.next() {
                        print("[W\(workerId)] ▶︎ reset | game \(gameIndex + 1)/\(games)")
                        fflush(stdout)
                        guard let result = await self.runSingleGame(engine: engine, hybrid: hybrid, workerId: workerId) else { continue }
                        await collector.add(result: result, index: gameIndex, total: games, workerId: workerId)
                    }
                }
            }
        }

        gpuWorkload.stop()
        return await collector.build()
    }

    func writeReport(report: Report) {
        let avg = report.scores.reduce(0, +) / max(1, report.scores.count)
        let maxScore = report.scores.max() ?? 0
        let minScore = report.scores.min() ?? 0
        let sorted = report.scores.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count/2]
        let avgMoves = report.movesPerGame.reduce(0, +) / max(1, report.movesPerGame.count)

        let lines: [String] = [
            "Games: \(report.scores.count)",
            "Avg Score: \(avg)",
            "Median Score: \(median)",
            "Max Score: \(maxScore)",
            "Min Score: \(minScore)",
            "Avg Moves: \(avgMoves)",
            "Max Tile Distribution:",
        ] + report.maxTileCounts.sorted(by: { $0.key < $1.key }).map { "  \($0.key): \($0.value)" }

        let outPath = "/Users/furyu/Desktop/2048-b-project/headless-test/report.txt"
        try? lines.joined(separator: "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
        print(lines.joined(separator: "\n"))
    }

    private func runSingleGame(engine: EngineClient, hybrid: HybridEvaluator, workerId: Int) async -> GameResult? {
        guard let state = await engine.reset() else { return nil }
        var board = state.board
        var score = state.score
        var isGameOver = state.is_game_over
        var moves = 0

        while !isGameOver {
            let hint = await engine.hint(board: board, score: score, timeLimitMs: 2000, maxDepth: 9)
            let cpuDir = hint?.direction
            let cpuValue = hint?.value ?? 0
            let gpuScores = hybrid.gpuDirectionScores(board: board, batchPerDir: 2048, rolloutDepth: 5)
            let finalDir = hybrid.combine(cpuDirection: cpuDir, cpuValue: cpuValue, gpuScores: gpuScores) ?? cpuDir
            if let finalDir, let resp = await engine.move(direction: finalDir) {
                board = resp.final_board
                score = resp.score
                isGameOver = resp.is_game_over
                moves += 1
                print("[W\(workerId)] moves=\(moves) | score=\(score)")
                fflush(stdout)
            } else {
                isGameOver = true
            }
        }
        let maxTile = board.max() ?? 0
        return GameResult(score: score, maxTile: maxTile, moves: moves)
    }
}
