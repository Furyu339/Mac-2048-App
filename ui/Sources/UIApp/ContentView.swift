import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var vm = GameViewModel()
    @StateObject private var keyMonitor = KeyMonitor()

    var body: some View {
        ZStack {
            background
            VStack(spacing: 22) {
                header
                scoreRow
                BoardSpriteView(model: vm.state)
                    .frame(width: 420, height: 420)
                    .padding(.horizontal, 20)
                controlPanel
                footer
            }
            .padding(.top, 28)
            .padding(.bottom, 30)
        }
        .overlay(
            KeyCatcherView(onKeyDown: { event in
                handleKey(event)
            }, allowFocus: true)
            .frame(width: 0, height: 0)
        )
        .onAppear {
            vm.start()
            NSApp.activate(ignoringOtherApps: true)
            keyMonitor.start { event in
                handleKey(event)
            }
        }
        .onDisappear {
            keyMonitor.stop()
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.12),
                    Color(red: 0.16, green: 0.12, blue: 0.18),
                    Color(red: 0.12, green: 0.15, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 280, height: 280)
                .offset(x: -160, y: -220)
                .blur(radius: 8)

            RoundedRectangle(cornerRadius: 60, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(width: 340, height: 200)
                .rotationEffect(.degrees(12))
                .offset(x: 140, y: -100)
                .blur(radius: 6)

            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .frame(width: 420, height: 320)
                .rotationEffect(.degrees(-8))
                .offset(x: 120, y: 200)
                .blur(radius: 24)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("三消 2048")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("滑动合并 + 连锁消除")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(vm.state.isGameOver ? "游戏结束" : "无尽模式")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(vm.state.isGameOver ? .red.opacity(0.9) : .white.opacity(0.7))
                Text("每回合补 2 块 (2/4/8/16)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 32)
    }

    private var scoreRow: some View {
        HStack(spacing: 14) {
            scoreCard(title: "当前分数", value: "\(vm.state.score)")
            scoreCard(title: "历史最高", value: "\(vm.state.bestScore)")
            battleCard
        }
        .padding(.horizontal, 28)
    }

    private func scoreCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(minWidth: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var battleCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("战况")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            HStack(spacing: 6) {
                Text("⬢\(vm.state.maxTile)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(vm.state.lastChainCount > 0 ? "连锁 x\(vm.state.lastChainCount)" : "无连锁")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            Text(vm.state.lastClearedCount > 0 ? "上回合消除 \(vm.state.lastClearedCount) 块" : "上回合无消除")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(minWidth: 148, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var controlPanel: some View {
        VStack(spacing: 10) {
            HStack {
                primaryButton(title: "新游戏") { vm.reset() }
                Spacer()
            }

            HStack(spacing: 10) {
                ruleBadge("三连及以上相邻同值会触发消除")
                ruleBadge("消除后保留一块并翻倍")
            }
        }
        .padding(.horizontal, 28)
    }

    private var footer: some View {
        HStack {
            Text("操作: 方向键 / WASD")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(vm.state.isGameOver ? "按“新游戏”再来一局" : "策略: 先合并再做连锁")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 32)
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.87, blue: 0.76))
                )
        }
        .buttonStyle(.plain)
    }

    private func ruleBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.86))
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    private func handleKey(_ event: NSEvent) {
        switch event.keyCode {
        case 123: vm.move(.left)
        case 124: vm.move(.right)
        case 125: vm.move(.down)
        case 126: vm.move(.up)
        default:
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "a": vm.move(.left)
                case "d": vm.move(.right)
                case "s": vm.move(.down)
                case "w": vm.move(.up)
                default: break
                }
            }
        }
    }
}
