import SwiftUI
import AppKit

struct KeyCatcherView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void
    var allowFocus: Bool

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onKeyDown = onKeyDown
        view.allowFocus = allowFocus
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyView {
            view.onKeyDown = onKeyDown
            view.allowFocus = allowFocus
            view.claimFocus()
        }
    }

    private final class KeyView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?
        var allowFocus: Bool = true

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            claimFocus()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            claimFocus()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        func claimFocus() {
            guard allowFocus else { return }
            DispatchQueue.main.async {
                if let window = self.window {
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(self)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard self.allowFocus else { return }
                if let window = self.window {
                    window.makeFirstResponder(self)
                }
            }
        }
    }
}
