import SpriteKit
import SwiftUI

final class GameScene: SKScene {
    private let boardNode = SKShapeNode()
    private let contentCrop = SKCropNode()
    private let gridLayer = SKNode()
    private let staticLayer = SKNode()
    private let overlayLayer = SKNode()

    private let padding: CGFloat = 12
    private let spacing: CGFloat = 10

    override init() {
        super.init(size: .zero)
        backgroundColor = .clear
        addChild(boardNode)
        addChild(contentCrop)
        contentCrop.addChild(gridLayer)
        contentCrop.addChild(staticLayer)
        contentCrop.addChild(overlayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutBoard()
    }

    func renderStatic(board: [Int], spawnedIndex: Int? = nil) {
        overlayLayer.removeAllChildren()
        staticLayer.removeAllChildren()
        layoutBoard()

        for index in 0..<board.count {
            let value = board[index]
            guard value > 0 else { continue }
            let tile = makeTile(value: value, size: cellSize())
            tile.position = point(for: index)
            staticLayer.addChild(tile)
            if let spawnedIndex, spawnedIndex == index {
                tile.alpha = 0.0
                tile.setScale(0.6)
                let appear = SKAction.group([
                    SKAction.fadeIn(withDuration: 0.16),
                    SKAction.scale(to: 1.05, duration: 0.16)
                ])
                let settle = SKAction.scale(to: 1.0, duration: 0.08)
                tile.run(SKAction.sequence([appear, settle]))
            }
        }
    }

    func playMove(
        movements: [Movement],
        mergedIndices: Set<Int>,
        finalBoard: [Int],
        previousBoard: [Int],
        spawnedIndex: Int?,
        moveDuration: TimeInterval,
        mergeDuration: TimeInterval
    ) {
        staticLayer.removeAllChildren()
        overlayLayer.removeAllChildren()
        layoutBoard()

        let cell = cellSize()
        let absorbDuration = mergeDuration
        let movingFrom = Set(movements.map { $0.from })

        for index in 0..<previousBoard.count {
            let value = previousBoard[index]
            guard value > 0 else { continue }
            if movingFrom.contains(index) { continue }
            let tile = makeTile(value: value, size: cell)
            tile.position = point(for: index)
            staticLayer.addChild(tile)
        }

        for move in movements {
            let tile = makeTile(value: move.value, size: cell)
            tile.position = point(for: move.from)
            overlayLayer.addChild(tile)

            let moveAction = SKAction.move(to: point(for: move.to), duration: moveDuration)
            moveAction.timingMode = .easeInEaseOut

            if move.isMerge {
                let absorb = SKAction.group([
                    SKAction.fadeOut(withDuration: absorbDuration),
                    SKAction.scale(to: 0.88, duration: absorbDuration)
                ])
                tile.run(SKAction.sequence([moveAction, absorb, .removeFromParent()]))
            } else {
                tile.run(SKAction.sequence([moveAction]))
            }
        }

        let mergeStart = moveDuration + absorbDuration * 0.3
        let mergeAction = SKAction.sequence([
            SKAction.wait(forDuration: mergeStart),
            SKAction.run { [weak self] in
                guard let self else { return }
                for idx in mergedIndices {
                    let value = finalBoard.indices.contains(idx) ? finalBoard[idx] : 0
                    guard value > 0 else { continue }
                    let tile = self.makeTile(value: value, size: cell)
                    tile.position = self.point(for: idx)
                    tile.alpha = 0.0
                    tile.setScale(0.92)
                    self.overlayLayer.addChild(tile)
                    let popUp = SKAction.group([
                        SKAction.fadeIn(withDuration: mergeDuration * 0.6),
                        SKAction.scale(to: 1.06, duration: mergeDuration * 0.6)
                    ])
                    let settle = SKAction.scale(to: 1.0, duration: mergeDuration * 0.4)
                    tile.run(SKAction.sequence([popUp, settle]))
                }
            }
        ])

        overlayLayer.run(mergeAction)

        let finishDelay = moveDuration + mergeDuration
        overlayLayer.run(SKAction.sequence([
            SKAction.wait(forDuration: finishDelay),
            SKAction.run { [weak self] in
                self?.renderStatic(board: finalBoard, spawnedIndex: spawnedIndex)
            }
        ]))
    }

    private func layoutBoard() {
        let rect = CGRect(origin: .zero, size: size)
        let path = CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil)
        boardNode.path = path
        boardNode.fillColor = SKColor(red: 0.16, green: 0.15, blue: 0.18, alpha: 0.85)
        boardNode.strokeColor = SKColor(white: 1.0, alpha: 0.06)
        boardNode.lineWidth = 1
        boardNode.position = .zero
        boardNode.zPosition = -2

        let mask = SKShapeNode(path: path)
        mask.fillColor = .white
        mask.strokeColor = .clear
        contentCrop.maskNode = mask
        contentCrop.position = .zero
        contentCrop.zPosition = -1

        gridLayer.removeAllChildren()
        let cell = cellSize()
        for row in 0..<GameConstants.size {
            for col in 0..<GameConstants.size {
                let originX = padding + CGFloat(col) * (cell.width + spacing)
                let originY = padding + CGFloat(row) * (cell.height + spacing)
                let rect = CGRect(x: originX, y: originY, width: cell.width, height: cell.height)
                let shape = SKShapeNode(rect: rect, cornerRadius: 12)
                shape.fillColor = SKColor(white: 1.0, alpha: 0.05)
                shape.strokeColor = SKColor(white: 1.0, alpha: 0.08)
                shape.lineWidth = 1
                shape.zPosition = 0
                gridLayer.addChild(shape)
            }
        }
    }

    private func cellSize() -> CGSize {
        let side = min(size.width, size.height)
        let cell = (side - padding * 2 - spacing * 3) / 4
        return CGSize(width: cell, height: cell)
    }

    private func point(for index: Int) -> CGPoint {
        let row = index / GameConstants.size
        let col = index % GameConstants.size
        let cell = cellSize()
        let x = padding + CGFloat(col) * (cell.width + spacing) + cell.width / 2
        let y = padding + CGFloat(GameConstants.size - 1 - row) * (cell.height + spacing) + cell.height / 2
        return CGPoint(x: x, y: y)
    }

    private func makeTile(value: Int, size: CGSize) -> SKNode {
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let shape = SKShapeNode(rect: rect, cornerRadius: 14)
        shape.fillColor = tileColor(value: value)
        shape.strokeColor = SKColor.clear
        shape.zPosition = 1

        let label = SKLabelNode(text: "\(value)")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = fontSize(for: value)
        label.fontColor = value <= 4 ? SKColor(red: 0.35, green: 0.30, blue: 0.26, alpha: 1.0) : .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 2
        shape.addChild(label)
        return shape
    }

    private func tileColor(value: Int) -> SKColor {
        switch value {
        case 2: return SKColor(red: 0.93, green: 0.89, blue: 0.85, alpha: 1.0)
        case 4: return SKColor(red: 0.92, green: 0.86, blue: 0.78, alpha: 1.0)
        case 8: return SKColor(red: 0.94, green: 0.67, blue: 0.46, alpha: 1.0)
        case 16: return SKColor(red: 0.93, green: 0.56, blue: 0.36, alpha: 1.0)
        case 32: return SKColor(red: 0.93, green: 0.45, blue: 0.34, alpha: 1.0)
        case 64: return SKColor(red: 0.92, green: 0.35, blue: 0.29, alpha: 1.0)
        case 128: return SKColor(red: 0.90, green: 0.77, blue: 0.38, alpha: 1.0)
        case 256: return SKColor(red: 0.90, green: 0.73, blue: 0.30, alpha: 1.0)
        case 512: return SKColor(red: 0.90, green: 0.69, blue: 0.23, alpha: 1.0)
        case 1024: return SKColor(red: 0.90, green: 0.64, blue: 0.16, alpha: 1.0)
        case 2048: return SKColor(red: 0.90, green: 0.59, blue: 0.10, alpha: 1.0)
        default: return SKColor(red: 0.24, green: 0.22, blue: 0.30, alpha: 1.0)
        }
    }

    private func fontSize(for value: Int) -> CGFloat {
        switch value {
        case 0..<100: return 32
        case 100..<1000: return 26
        case 1000..<10000: return 22
        default: return 18
        }
    }
}
