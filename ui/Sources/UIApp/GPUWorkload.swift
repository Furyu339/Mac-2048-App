import Foundation

final class GPUWorkloadController {
    private var task: Task<Void, Never>?
    private var task2: Task<Void, Never>?
    private var task3: Task<Void, Never>?
    private var task4: Task<Void, Never>?
    private var task5: Task<Void, Never>?
    private var task6: Task<Void, Never>?
    private var task7: Task<Void, Never>?
    private var task8: Task<Void, Never>?

    func start(boardProvider: @escaping () -> [Int]) {
        task?.cancel()
        task2?.cancel()
        task3?.cancel()
        task4?.cancel()
        task5?.cancel()
        task6?.cancel()
        task7?.cancel()
        task8?.cancel()
        task = Task.detached(priority: .userInitiated) {
            guard let evaluator = GPUEvaluator() else { return }
            while !Task.isCancelled {
                let baseBoard = await MainActor.run { boardProvider() }
                let cpuBatch = 32768
                let gpuSelfBatch = 262144
                let depth = 10
                let cpuBoards = GPUWorkloadController.generateBoards(base: baseBoard, batch: cpuBatch, depth: depth)
                let gpuBoards = GPUSelfGenerator.generateBoards(batch: gpuSelfBatch, depth: depth)
                let boards = cpuBoards + gpuBoards
                _ = evaluator.evaluate(boards: boards, boardCount: cpuBatch + gpuSelfBatch, iterations: 131072)
            }
        }
        task2 = Task.detached(priority: .userInitiated) {
            guard let evaluator = GPUEvaluator() else { return }
            while !Task.isCancelled {
                let boards = GPUSelfGenerator.generateBoards(batch: 131072, depth: 10)
                _ = evaluator.evaluate(boards: boards, boardCount: 131072, iterations: 131072)
            }
        }
        task3 = Task.detached(priority: .userInitiated) {
            guard let evaluator = GPUEvaluator() else { return }
            while !Task.isCancelled {
                let boards = GPUSelfGenerator.generateBoards(batch: 131072, depth: 10)
                _ = evaluator.evaluate(boards: boards, boardCount: 131072, iterations: 131072)
            }
        }
        task4 = Task.detached(priority: .userInitiated) {
            guard let evaluator = GPUEvaluator() else { return }
            while !Task.isCancelled {
                let boards = GPUSelfGenerator.generateBoards(batch: 65536, depth: 10)
                _ = evaluator.evaluate(boards: boards, boardCount: 65536, iterations: 131072)
            }
        }
        task5 = Task.detached(priority: .userInitiated) {
            guard let evaluator = GPUEvaluator() else { return }
            while !Task.isCancelled {
                let boards = GPUSelfGenerator.generateBoards(batch: 65536, depth: 10)
                _ = evaluator.evaluate(boards: boards, boardCount: 65536, iterations: 131072)
            }
        }
        task6 = Task.detached(priority: .userInitiated) {
            guard let evaluator = GPUEvaluator() else { return }
            while !Task.isCancelled {
                let boards = GPUSelfGenerator.generateBoards(batch: 65536, depth: 10)
                _ = evaluator.evaluate(boards: boards, boardCount: 65536, iterations: 131072)
            }
        }
        task7 = Task.detached(priority: .userInitiated) {
            guard let evaluator = GPUEvaluator() else { return }
            while !Task.isCancelled {
                let boards = GPUSelfGenerator.generateBoards(batch: 65536, depth: 10)
                _ = evaluator.evaluate(boards: boards, boardCount: 65536, iterations: 131072)
            }
        }
        task8 = Task.detached(priority: .userInitiated) {
            guard let evaluator = GPUEvaluator() else { return }
            while !Task.isCancelled {
                let boards = GPUSelfGenerator.generateBoards(batch: 65536, depth: 10)
                _ = evaluator.evaluate(boards: boards, boardCount: 65536, iterations: 131072)
            }
        }
    }

    func stop() {
        task?.cancel()
        task2?.cancel()
        task3?.cancel()
        task4?.cancel()
        task5?.cancel()
        task6?.cancel()
        task7?.cancel()
        task8?.cancel()
        task = nil
        task2 = nil
        task3 = nil
        task4 = nil
        task5 = nil
        task6 = nil
        task7 = nil
        task8 = nil
    }

    private static func generateBoards(base: [Int], batch: Int, depth: Int) -> [Int32] {
        var result: [Int32] = []
        result.reserveCapacity(batch * 16)
        for _ in 0..<batch {
            var board = base
            var localScore = 0
            for _ in 0..<depth {
                let dirs = Direction.allCases.shuffled()
                var moved = false
                for dir in dirs {
                    let outcome = GameLogic.move(board: board, direction: dir)
                    if outcome.changed {
                        board = outcome.board
                        localScore += outcome.score
                        _ = GameLogic.addRandomTile(board: &board)
                        moved = true
                        break
                    }
                }
                if !moved { break }
            }
            // write board into flat buffer
            for i in 0..<16 { result.append(Int32(board[i])) }
            // localScore intentionally unused; these boards represent real rollouts
        }
        return result
    }
}
