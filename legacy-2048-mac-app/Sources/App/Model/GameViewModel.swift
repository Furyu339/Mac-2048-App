import Foundation
import Combine

@MainActor
final class GameViewModel: ObservableObject {
    @Published var model: GameModel
    @Published var hintEnabled: Bool = true
    @Published var hintDirection: Direction? = nil
    @Published var isAutoPlaying: Bool = false
    @Published var autoInterval: Double = 0.0

    private var autoTask: Task<Void, Never>?
    private var pendingDirections: [Direction] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.model = GameModel()
        model.$isAnimating
            .removeDuplicates()
            .sink { [weak self] animating in
                guard let self else { return }
                if !animating {
                    self.dequeueIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    func reset() {
        model.reset()
        updateHintIfNeeded()
    }

    func move(_ direction: Direction) {
        guard !isAutoPlaying else { return }
        if model.isAnimating {
            enqueue(direction)
            return
        }
        performMove(direction)
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
        Task.detached(priority: .userInitiated) { [board = model.board, score = model.score] in
            let ai = ExpectimaxAI()
            let best = ai.bestMove(board: board, score: score, timeLimit: 1.0, maxDepth: 7)
            await MainActor.run {
                self.hintDirection = best
            }
        }
    }

    private func startAutoPlay() {
        autoTask?.cancel()
        autoTask = Task.detached(priority: .userInitiated) {
            while !Task.isCancelled {
                let board = await MainActor.run { self.model.board }
                let score = await MainActor.run { self.model.score }
                let ai = ExpectimaxAI()
                let best = ai.bestMove(board: board, score: score, timeLimit: 2.0, maxDepth: 9)

                let shouldContinue = await MainActor.run { () -> Bool in
                    if self.model.isAnimating {
                        return self.isAutoPlaying
                    }
                    if let best {
                        if self.model.move(best, speedMultiplier: 1.0) {
                            self.updateHintIfNeeded()
                        }
                    } else {
                        self.isAutoPlaying = false
                    }
                    if self.model.isGameOver {
                        self.isAutoPlaying = false
                    }
                    return self.isAutoPlaying
                }
                if !shouldContinue { break }

                let interval = max(0.0, await MainActor.run { self.autoInterval })
                if interval > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
        }
    }

    private func performMove(_ direction: Direction) {
        if model.move(direction, speedMultiplier: 1.0) {
            updateHintIfNeeded()
        }
    }

    private func enqueue(_ direction: Direction) {
        pendingDirections.append(direction)
    }

    private func dequeueIfNeeded() {
        guard !pendingDirections.isEmpty else { return }
        let next = pendingDirections.removeFirst()
        performMove(next)
    }

    // 纯队列模式：不加速
}
