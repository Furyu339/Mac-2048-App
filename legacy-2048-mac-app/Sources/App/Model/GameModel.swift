import Foundation
import Combine

final class GameModel: ObservableObject {
    static let baseMoveDuration: TimeInterval = 0.22
    static let baseMergeDuration: TimeInterval = 0.14

    @Published private(set) var board: [Int]
    @Published private(set) var score: Int
    @Published private(set) var bestScore: Int
    @Published private(set) var mergedIndices: Set<Int>
    @Published private(set) var spawnedIndex: Int?
    @Published private(set) var isGameOver: Bool
    @Published private(set) var previousBoard: [Int]
    @Published private(set) var movementSnapshot: [Movement]
    @Published private(set) var movementTick: Int
    @Published private(set) var isAnimating: Bool
    @Published private(set) var currentMoveDuration: TimeInterval
    @Published private(set) var currentMergeDuration: TimeInterval

    private let bestScoreKey = "TwoZeroFourEightBestScore"

    init() {
        self.board = Array(repeating: 0, count: GameLogic.boardCount)
        self.score = 0
        self.bestScore = UserDefaults.standard.integer(forKey: bestScoreKey)
        self.mergedIndices = []
        self.spawnedIndex = nil
        self.isGameOver = false
        self.previousBoard = Array(repeating: 0, count: GameLogic.boardCount)
        self.movementSnapshot = []
        self.movementTick = 0
        self.isAnimating = false
        self.currentMoveDuration = Self.baseMoveDuration
        self.currentMergeDuration = Self.baseMergeDuration
        reset()
    }

    func reset() {
        board = Array(repeating: 0, count: GameLogic.boardCount)
        previousBoard = board
        score = 0
        mergedIndices = []
        spawnedIndex = nil
        isGameOver = false
        movementSnapshot = []
        movementTick += 1
        isAnimating = false
        currentMoveDuration = Self.baseMoveDuration
        currentMergeDuration = Self.baseMergeDuration
        _ = GameLogic.addRandomTile(board: &board)
        _ = GameLogic.addRandomTile(board: &board)
    }

    func move(_ direction: Direction, speedMultiplier: Double = 1.0) -> Bool {
        let outcome = GameLogic.move(board: board, direction: direction)
        guard outcome.changed else { return false }
        previousBoard = board
        board = outcome.board
        score += outcome.score
        mergedIndices = outcome.mergedIndices
        spawnedIndex = GameLogic.addRandomTile(board: &board)
        movementTick += 1
        let currentTick = movementTick
        movementSnapshot = outcome.movements.filter { $0.fromIndex != $0.toIndex || $0.isMerge }
        isAnimating = true
        currentMoveDuration = Self.baseMoveDuration
        currentMergeDuration = Self.baseMergeDuration
        let total = currentMoveDuration + currentMergeDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self, self.movementTick == currentTick else { return }
            self.movementSnapshot = []
            self.isAnimating = false
        }
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: bestScoreKey)
        }
        isGameOver = !GameLogic.canMove(board: board)
        return true
    }
}
