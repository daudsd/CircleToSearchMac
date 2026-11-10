import Foundation
import Carbon.HIToolbox
import Security

extension Notification.Name {
    static let hotKeyChanged = Notification.Name("CircleSearch.hotKeyChanged")
    static let openSettings = Notification.Name("CircleSearch.openSettings")
}

/// The global shortcuts you can pick in Settings.
enum HotKeyPreset: String, CaseIterable, Identifiable {
    case optionSpace
    case optionShiftSpace
    case commandShift2
    case controlOptionS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .optionShiftSpace: return "⌥⇧ Space"
        case .commandShift2: return "⌘⇧2"
        case .controlOptionS: return "⌃⌥S"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .optionSpace, .optionShiftSpace: return UInt32(kVK_Space)
        case .commandShift2: return UInt32(kVK_ANSI_2)
        case .controlOptionS: return UInt32(kVK_ANSI_S)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace: return UInt32(optionKey)
        case .optionShiftSpace: return UInt32(optionKey | shiftKey)
        case .commandShift2: return UInt32(cmdKey | shiftKey)
        case .controlOptionS: return UInt32(controlKey | optionKey)
        }
    }
}

/// UserDefaults keys and defaults. SwiftUI views use the same keys via @AppStorage.
enum Prefs {
    static let hotKeyKey = "hotKey"
    static let targetLanguageKey = "targetLanguage"
    static let claudeModelKey = "claudeModel"
    static let claudePromptKey = "claudePrompt"

    static let defaultModel = "claude-haiku-5-5"
    static let defaultPrompt = "What is this? Answer briefly."
    static let defaultTargetLanguage = "en"

    static var hotKey: HotKeyPreset {
        HotKeyPreset(rawValue: UserDefaults.standard.string(forKey: hotKeyKey) ?? "") ?? .optionSpace
    }

    static var claudeModel: String {
        let value = UserDefaults.standard.string(forKey: claudeModelKey) ?? ""
        return value.trimmingCharacters(in: .whitespaces).isEmpty ? defaultModel : value
    }

    static var claudePrompt: String {
        let value = UserDefaults.standard.string(forKey: claudePromptKey) ?? ""
        return value.trimmingCharacters(in: .whitespaces).isEmpty ? defaultPrompt : value
    }

    static var apiKey: String? {
        get { Keychain.get("anthropic-api-key") }
        set { Keychain.set(newValue ?? "", for: "anthropic-api-key") }
    }
}

/// Minimal Keychain wrapper for the Anthropic API key.
enum Keychain {
    private static let service = "com.daud.CircleSearch"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func set(_ value: String, for account: String) {
        let query = baseQuery(account)
        SecItemDelete(query as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
