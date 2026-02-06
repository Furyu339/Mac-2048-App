import Foundation

@MainActor
final class GameViewModel: ObservableObject {
    @Published var state = GameState()
    @Published var hintEnabled: Bool = true
    @Published var hintDirection: Direction? = nil
    @Published var isHintComputing: Bool = false

    private var hintTask: Task<Void, Never>?
    private var hintToken: Int = 0
    private let hintClient = EngineClient()

    func start() {
        Task {
            _ = await EngineClient.shared.reset().map { resp in
                state.applyState(board: resp.board, score: resp.score, bestScore: resp.best_score, isGameOver: resp.is_game_over)
            }
            updateHintIfNeeded()
        }
    }

    func reset() {
        Task {
            if let resp = await EngineClient.shared.reset() {
                state.applyState(board: resp.board, score: resp.score, bestScore: resp.best_score, isGameOver: resp.is_game_over)
            }
            updateHintIfNeeded()
        }
    }

    func move(_ direction: Direction) {
        if state.isAnimating { return }
        Task {
            if let resp = await EngineClient.shared.move(direction: direction) {
                applyMoveResponse(resp)
            }
            updateHintIfNeeded()
        }
    }

    func updateHintIfNeeded() {
        hintTask?.cancel()
        hintTask = nil

        guard hintEnabled else {
            hintDirection = nil
            isHintComputing = false
            return
        }

        isHintComputing = true
        hintToken += 1
        let token = hintToken
        hintTask = Task.detached(priority: .userInitiated) { [board = state.board, score = state.score] in
            let resp = await self.hintClient.hint(board: board, score: score, timeLimitMs: 1200, maxDepth: 7)
            let cpuDir = resp?.direction
            let cpuValue = resp?.value ?? 0
            let hybrid = HybridEvaluator()
            let gpuScores = hybrid.gpuDirectionScores(board: board, batchPerDir: 512, rolloutDepth: 3)
            let combined = hybrid.combine(cpuDirection: cpuDir, cpuValue: cpuValue, gpuScores: gpuScores)
            await MainActor.run {
                guard self.hintEnabled, self.hintToken == token else { return }
                self.hintDirection = combined ?? cpuDir
                self.isHintComputing = false
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
