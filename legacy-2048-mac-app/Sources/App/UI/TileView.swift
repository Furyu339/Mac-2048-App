import SwiftUI

struct TileView: View {
    let value: Int
    let isMerged: Bool
    let isSpawned: Bool

    private var bgColor: Color { TilePalette.background(for: value) }
    private var textColor: Color { value <= 4 ? TilePalette.darkText : .white }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(bgColor)
                .shadow(color: Color.black.opacity(value == 0 ? 0 : 0.15), radius: 6, x: 0, y: 3)

            if value > 0 {
                Text("\(value)")
                    .font(.system(size: fontSize(for: value), weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                    .minimumScaleFactor(0.5)
            }
        }
        .scaleEffect(1.0)
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

private enum TilePalette {
    static let darkText = Color(red: 0.35, green: 0.30, blue: 0.26)
    static func background(for value: Int) -> Color {
        switch value {
        case 0: return Color(red: 0.18, green: 0.17, blue: 0.20).opacity(0.35)
        case 2: return Color(red: 0.93, green: 0.89, blue: 0.85)
        case 4: return Color(red: 0.92, green: 0.86, blue: 0.78)
        case 8: return Color(red: 0.94, green: 0.67, blue: 0.46)
        case 16: return Color(red: 0.93, green: 0.56, blue: 0.36)
        case 32: return Color(red: 0.93, green: 0.45, blue: 0.34)
        case 64: return Color(red: 0.92, green: 0.35, blue: 0.29)
        case 128: return Color(red: 0.90, green: 0.77, blue: 0.38)
        case 256: return Color(red: 0.90, green: 0.73, blue: 0.30)
        case 512: return Color(red: 0.90, green: 0.69, blue: 0.23)
        case 1024: return Color(red: 0.90, green: 0.64, blue: 0.16)
        case 2048: return Color(red: 0.90, green: 0.59, blue: 0.10)
        default: return Color(red: 0.24, green: 0.22, blue: 0.30)
        }
    }
}
