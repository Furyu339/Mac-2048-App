import Foundation

@MainActor
final class GameViewModel: ObservableObject {
    @Published var state = GameState()
    @Published var hintEnabled: Bool = true
    @Published var hintDirection: Direction? = nil
    @Published var isAutoPlaying: Bool = false
    @Published var autoInterval: Double = 0.0

    private var autoTask: Task<Void, Never>?
    private let gpuWorkload = GPUWorkloadController()
    private let engineStress = EngineStressController()

    func start() {
        Task {
            _ = await EngineClient.shared.reset().map { resp in
                state.applyState(board: resp.board, score: resp.score, bestScore: resp.best_score, isGameOver: resp.is_game_over)
            }
            updateHintIfNeeded()
            await MainActor.run {
                self.gpuWorkload.start { self.state.board }
                self.engineStress.start { self.state.board }
            }
        }
    }

    func reset() {
        Task {
            if let resp = await EngineClient.shared.reset() {
                state.applyState(board: resp.board, score: resp.score, bestScore: resp.best_score, isGameOver: resp.is_game_over)
            }
            updateHintIfNeeded()
            await MainActor.run {
                self.gpuWorkload.start { self.state.board }
                self.engineStress.start { self.state.board }
            }
        }
    }

    func move(_ direction: Direction) {
        guard !isAutoPlaying else { return }
        if state.isAnimating { return }
        Task {
            if let resp = await EngineClient.shared.move(direction: direction) {
                applyMoveResponse(resp)
            }
            updateHintIfNeeded()
        }
    }

    func toggleAutoPlay() {
        isAutoPlaying.toggle()
        if isAutoPlaying {
            startAutoPlay()
        } else {
            autoTask?.cancel()
            autoTask = nil
        }
    }

    func updateHintIfNeeded() {
        guard hintEnabled else {
            hintDirection = nil
            return
        }
        Task.detached(priority: .userInitiated) { [board = state.board, score = state.score] in
            let resp = await EngineClient.shared.hint(board: board, score: score, timeLimitMs: 1200, maxDepth: 7)
            let cpuDir = resp?.direction
            let cpuValue = resp?.value ?? 0
            let hybrid = HybridEvaluator()
            let gpuScores = hybrid.gpuDirectionScores(board: board, batchPerDir: 512, rolloutDepth: 3)
            let combined = hybrid.combine(cpuDirection: cpuDir, cpuValue: cpuValue, gpuScores: gpuScores)
            await MainActor.run {
                self.hintDirection = combined ?? cpuDir
            }
        }
    }

    private func startAutoPlay() {
        autoTask?.cancel()
        autoTask = Task.detached(priority: .userInitiated) {
            while !Task.isCancelled {
                let shouldContinue = await MainActor.run { () -> Bool in
                    if self.state.isAnimating { return self.isAutoPlaying }
                    return self.isAutoPlaying
                }
                if !shouldContinue { break }

                let board = await MainActor.run { self.state.board }
                let score = await MainActor.run { self.state.score }
                let cpuHint = await EngineClient.shared.hint(board: board, score: score, timeLimitMs: 2000, maxDepth: 9)
                let cpuDir = cpuHint?.direction
                let cpuValue = cpuHint?.value ?? 0
                let hybrid = HybridEvaluator()
                let gpuScores = hybrid.gpuDirectionScores(board: board, batchPerDir: 2048, rolloutDepth: 5)
                let finalDir = hybrid.combine(cpuDirection: cpuDir, cpuValue: cpuValue, gpuScores: gpuScores) ?? cpuDir
                if let finalDir, let resp = await EngineClient.shared.move(direction: finalDir) {
                    await MainActor.run {
                        self.applyMoveResponse(resp)
                        self.updateHintIfNeeded()
                    }
                }

                let interval = await MainActor.run { self.autoInterval }
                if interval > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
        }
    }

    private func applyMoveResponse(_ resp: EngineMoveResultResponse) {
        state.applyMove(
            previous: resp.previous_board,
            final: resp.final_board,
            movements: resp.movements,
            merged: resp.merged_indices,
            spawnedIndex: resp.spawned_index,
            score: resp.score,
            bestScore: resp.best_score,
            isGameOver: resp.is_game_over
        )
    }
}
