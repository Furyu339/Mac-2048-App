import SwiftUI
import SpriteKit

struct BoardSpriteView: View {
    @ObservedObject var model: GameModel
    @State private var scene = GameScene()

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            SpriteView(scene: scene)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onAppear {
                    scene.scaleMode = .resizeFill
                    scene.size = CGSize(width: side, height: side)
                    scene.renderStatic(board: model.board, spawnedIndex: model.spawnedIndex)
                }
                .onChange(of: side) { newSide in
                    scene.size = CGSize(width: newSide, height: newSide)
                    scene.renderStatic(board: model.board, spawnedIndex: model.spawnedIndex)
                }
                .onChange(of: model.movementTick) { _ in
                    if !model.movementSnapshot.isEmpty {
                        scene.playMove(
                            movements: model.movementSnapshot,
                            mergedIndices: model.mergedIndices,
                            finalBoard: model.board,
                            previousBoard: model.previousBoard,
                            spawnedIndex: model.spawnedIndex,
                            moveDuration: model.currentMoveDuration,
                            mergeDuration: model.currentMergeDuration
                        )
                    } else {
                        scene.renderStatic(board: model.board, spawnedIndex: model.spawnedIndex)
                    }
                }
                .onChange(of: model.board) { _ in
                    if model.movementSnapshot.isEmpty {
                        scene.renderStatic(board: model.board, spawnedIndex: model.spawnedIndex)
                    }
                }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
