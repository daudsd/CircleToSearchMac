import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.hotKeyKey) private var hotKey = HotKeyPreset.optionSpace.rawValue
    @AppStorage(Prefs.targetLanguageKey) private var targetLanguage = Prefs.defaultTargetLanguage
    @AppStorage(Prefs.claudeModelKey) private var claudeModel = Prefs.defaultModel
    @AppStorage(Prefs.claudePromptKey) private var claudePrompt = Prefs.defaultPrompt

    @State private var apiKey = ""
    @State private var apiKeySaved = Prefs.apiKey != nil
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hasScreenAccess = CGPreflightScreenCaptureAccess()
    @State private var loginError: String?

    init() {}

    var body: some View {
        Form {
            Section("Capture") {
                Picker("Shortcut", selection: $hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                }
                .onChange(of: hotKey) { _, _ in
                    NotificationCenter.default.post(name: .hotKeyChanged, object: nil)
                }

                HStack {
                    Text("Screen Recording")
                    Spacer()
                    if hasScreenAccess {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Translate") {
                LabeledContent("Translate to") {
                    LanguagePicker(selection: $targetLanguage)
                        .frame(maxWidth: 220)
                }
                Text("Uses Apple's on-device translation, trying the Apple Intelligence models first (macOS 26.4+, needs Apple Intelligence turned on). These cover extra languages such as Norwegian. Anything marked · Claude isn't available from Apple on this Mac and is translated by Claude, using the API key below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ask Claude") {
                HStack {
                    SecureField(apiKeySaved ? "Saved in Keychain" : "Anthropic API key (sk-ant-…)", text: $apiKey)
                    Button(apiKey.isEmpty && apiKeySaved ? "Remove" : "Save") {
                        Prefs.apiKey = apiKey
                        apiKey = ""
                        apiKeySaved = Prefs.apiKey != nil
                    }
                    .disabled(apiKey.isEmpty && !apiKeySaved)
                }
                TextField("Model", text: $claudeModel)
                TextField("First question", text: $claudePrompt)
                Link("Get an API key at console.anthropic.com",
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 540)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasScreenAccess = CGPreflightScreenCaptureAccess()
        }
    }
}
