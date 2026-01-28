import Foundation

struct BoardHash {
    static func hash(board: [Int], depth: Int, isPlayer: Bool) -> UInt64 {
        var h: UInt64 = isPlayer ? 0x9E3779B185EBCA87 : 0xC2B2AE3D27D4EB4F
        for v in board {
            h = h &* 1099511628211 ^ UInt64(v &* 31 + 7)
        }
        h ^= UInt64(depth &* 131)
        return h
    }
}
