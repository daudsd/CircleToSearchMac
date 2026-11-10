// Prints what Apple's Translation framework can do on this Mac for Norwegian.
// Run:  swift ~/Documents/CircleSearch/Tools/translation-check.swift
import Foundation
import NaturalLanguage
import Translation
#if canImport(FoundationModels)
import FoundationModels
#endif

let nb = Locale.Language(identifier: "nb")
let en = Locale.Language(identifier: "en")
let sample = "Dette er en enkel test av oversettelse fra norsk bokmål til engelsk."

print("macOS:", ProcessInfo.processInfo.operatingSystemVersionString)

#if canImport(FoundationModels)
if #available(macOS 26.0, *) {
    print("Apple Intelligence:", SystemLanguageModel.default.availability)
}
#endif

let recognizer = NLLanguageRecognizer()
recognizer.processString(sample)
print("NaturalLanguage detects sample as:", recognizer.dominantLanguage?.rawValue ?? "nil")

func report(_ label: String, _ availability: LanguageAvailability) async {
    let ids = await availability.supportedLanguages.map { $0.minimalIdentifier }.sorted()
    print("\n[\(label)] \(ids.count) languages:")
    print("  " + ids.joined(separator: " "))
    let norwegian = ids.filter { $0.hasPrefix("nb") || $0.hasPrefix("no") || $0.hasPrefix("nn") }
    print("  Norwegian entries:", norwegian.isEmpty ? "none" : norwegian.joined(separator: ", "))
    for (from, to) in [(nb, en), (en, nb)] {
        let status = try? await availability.status(from: from, to: to)
        print("  status \(from.minimalIdentifier) -> \(to.minimalIdentifier):", status.map { "\($0)" } ?? "error")
    }
    do {
        let status = try await availability.status(for: sample, to: en)
        print("  status(for: Norwegian sample -> en):", status)
    } catch {
        print("  status(for: Norwegian sample -> en) error:", error)
    }
}

await report("standard / lowLatency", LanguageAvailability())

if #available(macOS 26.4, *) {
    await report("highFidelity / Apple Intelligence", LanguageAvailability(preferredStrategy: .highFidelity))

    print("\nTrying a real translation nb -> en with the Apple Intelligence model…")
    do {
        let session = TranslationSession(installedSource: nb, target: en, preferredStrategy: .highFidelity)
        let response = try await session.translate(sample)
        print("  OK:", response.targetText)
    } catch {
        print("  Failed:", error)
    }
} else {
    print("\nhighFidelity strategy needs macOS 26.4 or later.")
}
