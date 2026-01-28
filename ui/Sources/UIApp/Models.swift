import Foundation

enum Direction: String, CaseIterable, Codable {
    case up, down, left, right

    var label: String {
        switch self {
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        }
    }

    var arrow: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        }
    }
}

struct Movement: Identifiable, Codable {
    let id = UUID()
    let from: Int
    let to: Int
    let value: Int
    let isMerge: Bool

    enum CodingKeys: String, CodingKey {
        case from, to, value
        case isMerge = "is_merge"
    }
}

enum GameConstants {
    static let size = 4
    static let boardCount = 16
    static let moveDuration: TimeInterval = 0.22
    static let mergeDuration: TimeInterval = 0.14
}

@MainActor
final class GameState: ObservableObject {
    @Published var board: [Int] = Array(repeating: 0, count: GameConstants.boardCount)
    @Published var score: Int = 0
    @Published var bestScore: Int = 0
    @Published var mergedIndices: Set<Int> = []
    @Published var spawnedIndex: Int? = nil
    @Published var isGameOver: Bool = false
    @Published var previousBoard: [Int] = Array(repeating: 0, count: GameConstants.boardCount)
    @Published var movementSnapshot: [Movement] = []
    @Published var movementTick: Int = 0
    @Published var isAnimating: Bool = false
    @Published var currentMoveDuration: TimeInterval = GameConstants.moveDuration
    @Published var currentMergeDuration: TimeInterval = GameConstants.mergeDuration

    func applyState(board: [Int], score: Int, bestScore: Int, isGameOver: Bool) {
        self.board = board
        self.score = score
        self.bestScore = bestScore
        self.isGameOver = isGameOver
        self.movementSnapshot = []
        self.mergedIndices = []
        self.spawnedIndex = nil
        self.previousBoard = board
        self.isAnimating = false
        self.movementTick += 1
    }

    func applyMove(previous: [Int], final: [Int], movements: [Movement], merged: [Int], spawnedIndex: Int?, score: Int, bestScore: Int, isGameOver: Bool) {
        self.previousBoard = previous
        self.board = final
        self.score = score
        self.bestScore = bestScore
        self.mergedIndices = Set(merged)
        self.spawnedIndex = spawnedIndex
        self.movementSnapshot = movements.filter { $0.from != $0.to || $0.isMerge }
        self.movementTick += 1
        self.isAnimating = true
        self.currentMoveDuration = GameConstants.moveDuration
        self.currentMergeDuration = GameConstants.mergeDuration
        let total = self.currentMoveDuration + self.currentMergeDuration
        let tick = self.movementTick
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            guard self.movementTick == tick else { return }
            self.movementSnapshot = []
            self.isAnimating = false
        }
        self.isGameOver = isGameOver
    }
}
