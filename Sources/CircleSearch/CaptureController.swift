import AppKit

/// Freezes the screen(s) and shows the drawing overlay.
@MainActor
final class CaptureController {
    private var windows: [OverlayWindow] = []
    private var isStarting = false

    var isActive: Bool { !windows.isEmpty }

    /// The hotkey toggles: press once to start, again to cancel.
    func toggle() {
        if isActive { close() } else { start() }
    }

    func start() {
        guard !isActive, !isStarting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }
        isStarting = true
        Task {
            defer { self.isStarting = false }
            do {
                let shots = try await ScreenCapturer.captureAllScreens()
                guard !shots.isEmpty else { return }
                // The older API still forces activation reliably for a menu-bar app.
                NSApp.activate(ignoringOtherApps: true)
                for shot in shots {
                    let window = OverlayWindow(screen: shot.screen, image: shot.image, controller: self)
                    window.orderFrontRegardless()
                    windows.append(window)
                }
                let mouse = NSEvent.mouseLocation
                let target = windows.first(where: { $0.frame.contains(mouse) }) ?? windows.first
                target?.makeKeyAndOrderFront(nil)
            } catch {
                showError(error)
            }
        }
    }

    func close() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }

    /// When you start drawing on one display, clear any selection on the others.
    func selectionStarted(in view: OverlayView) {
        for window in windows {
            if let other = window.contentView as? OverlayView, other !== view {
                other.clearSelection()
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "Turn on Circle Search in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't capture the screen"
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
