import Foundation
import NaturalLanguage
import Translation

/// Picks the best Apple translation model for a piece of text.
///
/// macOS 26.4 added `TranslationSession.Strategy`. `.highFidelity` uses the
/// Apple Intelligence models, which "support additional languages" (Apple lists
/// Norwegian as an Apple Intelligence language). `.lowLatency` is the older
/// downloadable model set, which is what you get by default.
enum AppleTranslation {
    struct Match {
        let configuration: TranslationSession.Configuration
        let appleIntelligence: Bool
        let source: Locale.Language?
        /// Languages already on the Mac, so we can translate directly without a download prompt.
        let installed: Bool
    }

    struct Check {
        var match: Match?
        /// Human-readable summary of what was tried, shown when Apple can't translate.
        var summary: String
        var sameLanguage = false
    }

    /// Languages Apple can translate on this Mac, from either model set.
    static func supportedLanguages() async -> [Locale.Language] {
        var languages = await LanguageAvailability().supportedLanguages
        if #available(macOS 26.4, *) {
            let intelligence = await LanguageAvailability(preferredStrategy: .highFidelity).supportedLanguages
            languages.append(contentsOf: intelligence)
        }
        return languages
    }

    /// Detects the text's language with NaturalLanguage (recognises Norwegian as "nb").
    static func detectLanguage(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage, lang != .undetermined else { return nil }
        return Locale.Language(identifier: lang.rawValue)
    }

    /// Finds a configuration that can translate `text` into `target`.
    static func check(text: String, target: Locale.Language) async -> Check {
        let source = detectLanguage(text)
        let sourceID = source?.minimalIdentifier ?? "unknown"
        let targetID = target.minimalIdentifier

        if let source, source.languageCode == target.languageCode {
            return Check(match: nil, summary: "The text is already in \(name(targetID)).", sameLanguage: true)
        }

        var notes: [String] = []

        if #available(macOS 26.4, *) {
            let availability = LanguageAvailability(preferredStrategy: .highFidelity)
            let aiStatus = await checkStatus(availability, text: text, source: source, target: target)
            notes.append("Apple Intelligence model: \(describe(aiStatus))")
            if isUsable(aiStatus) {
                let config = TranslationSession.Configuration(
                    source: source, target: target, preferredStrategy: .highFidelity
                )
                let match = Match(configuration: config, appleIntelligence: true,
                                  source: source, installed: isInstalled(aiStatus))
                return Check(match: match, summary: "")
            }
        } else {
            notes.append("Apple Intelligence model: needs macOS 26.4+")
        }

        let standardStatus = await checkStatus(LanguageAvailability(), text: text, source: source, target: target)
        notes.append("standard model: \(describe(standardStatus))")
        if isUsable(standardStatus) {
            let config = TranslationSession.Configuration(source: source, target: target)
            let match = Match(configuration: config, appleIntelligence: false,
                              source: source, installed: isInstalled(standardStatus))
            return Check(match: match, summary: "")
        }

        let summary = "Apple can't translate \(name(sourceID)) → \(name(targetID)) on this Mac ("
            + notes.joined(separator: ", ") + ")."
        return Check(match: nil, summary: summary)
    }

    /// Checks with the detected source language first, then lets the framework detect it.
    private static func checkStatus(
        _ availability: LanguageAvailability,
        text: String,
        source: Locale.Language?,
        target: Locale.Language
    ) async -> LanguageAvailability.Status? {
        if let source {
            let explicit = try? await availability.status(from: source, to: target)
            if isUsable(explicit) { return explicit }
        }
        return try? await availability.status(for: text, to: target)
    }

    /// Translates with a session created directly (no SwiftUI), the same way the
    /// Tools/translation-check.swift script does. Returns nil when that isn't possible
    /// (older macOS, unknown source language, or languages still need downloading).
    static func translateDirectly(_ text: String, match: Match, target: Locale.Language) async throws -> String? {
        guard #available(macOS 26.4, *), match.installed, let source = match.source else { return nil }
        let session = TranslationSession(
            installedSource: source,
            target: target,
            preferredStrategy: match.appleIntelligence ? .highFidelity : .lowLatency
        )
        return try await session.translate(text).targetText
    }

    private static func isInstalled(_ status: LanguageAvailability.Status?) -> Bool {
        if case .some(.installed) = status { return true }
        return false
    }

    private static func isUsable(_ status: LanguageAvailability.Status?) -> Bool {
        switch status {
        case .some(.installed), .some(.supported): return true
        default: return false
        }
    }

    private static func describe(_ status: LanguageAvailability.Status?) -> String {
        switch status {
        case .some(.installed): return "installed"
        case .some(.supported): return "supported"
        case .some(.unsupported): return "unsupported"
        case .none: return "couldn't check"
        default: return "unknown"
        }
    }

    static func name(_ id: String) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: id) ?? id
    }
}
