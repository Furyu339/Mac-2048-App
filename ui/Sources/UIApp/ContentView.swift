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
        .onChange(of: vm.hintEnabled) { _ in
            vm.updateHintIfNeeded()
        }
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
                Text("2048")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("方案 B · 计算引擎分离")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(vm.state.isGameOver ? "游戏结束" : "状态正常")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(vm.state.isGameOver ? .red.opacity(0.9) : .white.opacity(0.7))
                Text("目标: 2048+")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 32)
    }

    private var scoreRow: some View {
        HStack(spacing: 14) {
            scoreCard(title: "当前分数", value: "\(vm.state.score)")
            scoreCard(title: "最高分", value: "\(vm.state.bestScore)")
            hintCard
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

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("提示")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            HStack(spacing: 6) {
                Text(vm.isHintComputing ? "…" : (vm.hintDirection?.arrow ?? "—"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(vm.isHintComputing ? "计算中" : (vm.hintDirection?.label ?? "无"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
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

    private var controlPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                primaryButton(title: "新游戏") { vm.reset() }
                toggleButton(title: vm.hintEnabled ? "提示已开" : "提示已关", isOn: vm.hintEnabled) {
                    vm.hintEnabled.toggle()
                }
                toggleButton(title: "日志", isOn: false) {
                    AILogger.shared.toggleWindow()
                }
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
            Text("引擎计算最优解")
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

    private func toggleButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isOn ? Color(red: 0.35, green: 0.32, blue: 0.50) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(isOn ? 0.12 : 0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
