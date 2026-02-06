import Foundation

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
    let metrics: EngineMetrics
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

struct EngineMetrics: Codable {
    let nodes: UInt64
    let cache_hits: UInt64
    let deadline_hits: UInt64
    let elapsed_ms: UInt64
}

final class EngineClient {
    static let shared = EngineClient()

    private let queue = DispatchQueue(label: "engine.client.queue")
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextId: UInt64 = 1
    private var pending: [UInt64: (Data) -> Void] = [:]

    func startIfNeeded() {
        if process != nil { return }
        let proc = Process()
        guard let path = locateEngineBinary() else {
            return
        }
        proc.executableURL = URL(fileURLWithPath: path)
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = nil
        do {
            try proc.run()
        } catch {
            return
        }
        process = proc
        stdinPipe = inPipe
        stdoutPipe = outPipe
        readOutput()
    }

    func reset() async -> EngineStateResponse? {
        let id = nextRequestId()
        let req: [String: Any] = ["type": "reset", "id": id]
        AILogger.shared.append("发送: reset \(id)")
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
        AILogger.shared.append("发送: hint \(id) depth=\(maxDepth) time=\(timeLimitMs)ms")
        return await send(request: req) { data in
            try? JSONDecoder().decode(EngineHintResponse.self, from: data)
        }
    }

    func move(direction: Direction) async -> EngineMoveResultResponse? {
        let id = nextRequestId()
        let req: [String: Any] = ["type": "move", "id": id, "direction": direction.rawValue]
        AILogger.shared.append("发送: move \(id) dir=\(direction.rawValue)")
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
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            self.queue.async {
                self.processBuffer(data)
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
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let id = obj["id"] as? UInt64 {
                if let type = obj["type"] as? String {
                    AILogger.shared.append("收到: \(type) \(id)")
                }
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

    private func locateEngineBinary() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let p = env["ENGINE_PATH"] { return p }
        let bundle = Bundle.main.bundleURL
        let bundleCandidate = bundle.appendingPathComponent("engine").path
        if FileManager.default.isExecutableFile(atPath: bundleCandidate) { return bundleCandidate }
        let cwd = FileManager.default.currentDirectoryPath
        let relCandidate = URL(fileURLWithPath: cwd).appendingPathComponent("../engine/target/release/engine").path
        if FileManager.default.isExecutableFile(atPath: relCandidate) { return relCandidate }
        let absCandidate = "/Users/furyu/Desktop/2048-b-project/engine/target/release/engine"
        if FileManager.default.isExecutableFile(atPath: absCandidate) { return absCandidate }
        return nil
    }
}
