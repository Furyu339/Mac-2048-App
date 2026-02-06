import Foundation
import Combine

@MainActor
final class GameViewModel: ObservableObject {
    @Published var state = GameState()
    @Published var lastMoveDirection: Direction? = nil

    private let defaults = UserDefaults.standard
    private let bestScoreKey = "match2048.bestScore"
    private var cancellables: Set<AnyCancellable> = []

    init() {
        state.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        let savedBest = defaults.integer(forKey: bestScoreKey)
        if savedBest > 0 {
            state.bestScore = savedBest
        }
    }

    func start() {
        if state.board.allSatisfy({ $0 == 0 }) {
            reset()
        }
    }

    func reset() {
        let board = GameLogic.createInitialBoard(seedCount: 2)
        let best = max(state.bestScore, defaults.integer(forKey: bestScoreKey))
        state.applyState(board: board, score: 0, bestScore: best, isGameOver: GameLogic.isGameOver(board: board))
    }

    func move(_ direction: Direction) {
        if state.isAnimating { return }
        if state.isGameOver { return }
        guard let turn = GameLogic.nextTurn(board: state.board, direction: direction) else { return }

        let (moveOutcome, resolveOutcome, spawnedIndices, finalBoard) = turn
        let merged = moveOutcome.mergedIndices.union(resolveOutcome.upgradedIndices)
        let gained = moveOutcome.score + resolveOutcome.score
        let score = state.score + gained
        let bestScore = max(state.bestScore, score)
        if bestScore > state.bestScore {
            defaults.set(bestScore, forKey: bestScoreKey)
        }

        let activeSpawned = spawnedIndices.filter { idx in
            finalBoard.indices.contains(idx) && finalBoard[idx] > 0
        }
        state.applyMove(
            previous: state.board,
            final: finalBoard,
            movements: moveOutcome.movements,
            merged: Array(merged),
            spawnedIndices: activeSpawned,
            score: score,
            bestScore: bestScore,
            isGameOver: GameLogic.isGameOver(board: finalBoard),
            chainCount: resolveOutcome.chainCount,
            clearedCount: resolveOutcome.clearedCount
        )
        lastMoveDirection = direction
    }
}
