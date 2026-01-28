import AppKit
import Foundation

final class KeyMonitor: ObservableObject {
    private var monitor: Any?
    private var handler: ((NSEvent) -> Void)?

    func start(handler: @escaping (NSEvent) -> Void) {
        self.handler = handler
        if monitor != nil { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handler?(event)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stop()
    }
}
