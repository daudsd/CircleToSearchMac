import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let capture = CaptureController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "circle.dashed",
            accessibilityDescription: "Circle Search"
        )
        buildMenu()

        HotKeyManager.shared.onPress = { [weak self] in self?.capture.toggle() }
        registerHotKey(showAlertOnFailure: true)

        NotificationCenter.default.addObserver(
            forName: .hotKeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.registerHotKey(showAlertOnFailure: true)
                self?.buildMenu()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .openSettings, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.openSettings()
            }
        }

        // Ask for Screen Recording permission on first launch.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        let start = NSMenuItem(
            title: "Circle to Search  (\(Prefs.hotKey.title))",
            action: #selector(startCapture),
            keyEquivalent: ""
        )
        start.target = self
        menu.addItem(start)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Circle Search", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func registerHotKey(showAlertOnFailure: Bool) {
        let preset = Prefs.hotKey
        guard !HotKeyManager.shared.register(preset), showAlertOnFailure else { return }
        let alert = NSAlert()
        alert.messageText = "\(preset.title) is already in use"
        alert.informativeText = "Another app is using this shortcut. Pick a different one in Circle Search Settings, or use the menu bar icon."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    @objc private func startCapture() {
        // Let the menu finish closing before we take the screenshot.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            self?.capture.toggle()
        }
    }

    @objc func openSettings() {
        capture.close()
        if settingsWindow == nil {
            let window = NSWindow(
                contentViewController: NSHostingController(rootView: SettingsView())
            )
            window.title = "Circle Search Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
