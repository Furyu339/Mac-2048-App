import AppKit

final class AILogger {
    static let shared = AILogger()

    private let lock = NSLock()
    private var buffer: [String] = []
    private var window: NSWindow?
    private var textView: NSTextView?

    private init() {}

    func toggleWindow() {
        if let window, window.isVisible {
            window.close()
            self.window = nil
            self.textView = nil
        } else {
            openWindow()
        }
    }

    func append(_ message: String) {
        let line = timestamped(message)
        lock.lock()
        buffer.append(line)
        let view = textView
        lock.unlock()

        guard let view else { return }
        DispatchQueue.main.async {
            view.textStorage?.append(NSAttributedString(string: line + "\n"))
            view.scrollToEndOfDocument(nil)
        }
    }

    private func openWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI 运行日志"
        window.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor

        scroll.documentView = textView
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)

        lock.lock()
        self.window = window
        self.textView = textView
        let existing = buffer
        lock.unlock()

        if !existing.isEmpty {
            textView.textStorage?.append(NSAttributedString(string: existing.joined(separator: "\n") + "\n"))
            textView.scrollToEndOfDocument(nil)
        }
    }

    private func timestamped(_ message: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "[\(formatter.string(from: Date()))] \(message)"
    }
}
