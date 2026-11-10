import AppKit
import SwiftUI
import Translation

// MARK: - Model

@MainActor
final class PanelModel: ObservableObject {
    enum Mode { case text, translate, claude }

    let image: CGImage
    private let onClose: @MainActor () -> Void
    private lazy var imageBase64: String? = image.scaled(maxDimension: 1568).pngData()?.base64EncodedString()

    @Published var mode: Mode = .text
    @Published var toast: String?

    // Text
    @Published var ocrText = ""
    @Published var ocrDone = false

    // Translation
    @Published var translationConfig: TranslationSession.Configuration?
    @Published var translatedText = ""
    @Published var isTranslating = false
    @Published var translationError: String?
    @Published var translatedViaClaude = false
    @Published var usedAppleIntelligence = false

    // Claude
    @Published var turns: [ChatTurn] = []
    @Published var claudeInput = ""
    @Published var claudeBusy = false
    @Published var claudeError: String?

    init(image: CGImage, onClose: @escaping @MainActor () -> Void) {
        self.image = image
        self.onClose = onClose
        Task { await runOCR() }
    }

    var hasText: Bool { !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func close() { onClose() }

    private func runOCR() async {
        ocrText = await TextRecognizer.recognize(image)
        ocrDone = true
    }

    // MARK: Actions

    func copyText() {
        guard hasText else { flash("No text found"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ocrText, forType: .string)
        flash("Copied text")
        after(0.35) { [weak self] in self?.close() }
    }

    func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
        flash("Copied image")
        after(0.35) { [weak self] in self?.close() }
    }

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        flash("Copied")
    }

    func searchLens() {
        let image = self.image
        close()
        LensSearch.open(image)
    }

    func startTranslate() {
        mode = .translate
        guard hasText, !isTranslating else { return }
        if translatedText.isEmpty || translationError != nil {
            restartTranslation()
        }
    }

    private var targetLanguageID: String {
        UserDefaults.standard.string(forKey: Prefs.targetLanguageKey) ?? Prefs.defaultTargetLanguage
    }

    func restartTranslation() {
        let targetID = targetLanguageID
        let language = Locale.Language(identifier: targetID)
        let text = ocrText
        translationError = nil
        translatedText = ""
        isTranslating = true

        Task {
            // Ask Apple whether it can translate this text (source is auto-detected) on this Mac,
            // trying the Apple Intelligence models first (they cover more languages, e.g. Norwegian).
            let check = await AppleTranslation.check(text: text, target: language)
            if check.sameLanguage {
                translationError = check.summary + " Pick another language above."
                isTranslating = false
                return
            }
            guard let match = check.match else {
                await translateWithClaude(text, targetID: targetID, appleReport: check.summary)
                return
            }

            translatedViaClaude = false
            usedAppleIntelligence = match.appleIntelligence

            // Preferred path: translate directly with the installed languages.
            do {
                if let result = try await AppleTranslation.translateDirectly(text, match: match, target: language) {
                    translatedText = result
                    isTranslating = false
                    return
                }
            } catch {
                await translateWithClaude(
                    text,
                    targetID: targetID,
                    appleReport: "Apple's translation failed: \(error.localizedDescription)"
                )
                return
            }

            // Languages still need downloading: use SwiftUI's .translationTask,
            // which can show the system download prompt.
            // A changed configuration makes SwiftUI run .translationTask again.
            // Same one as before: invalidate() bumps its version so it still re-runs.
            let key = "\(match.configuration.source?.minimalIdentifier ?? "auto")|\(targetID)|\(match.appleIntelligence)"
            if translationConfig != nil && key == lastConfigKey {
                translationConfig?.invalidate()
            } else {
                translationConfig = match.configuration
                lastConfigKey = key
            }
        }
    }

    private var lastConfigKey = ""

    func translate(using session: TranslationSession) async {
        do {
            let response = try await session.translate(ocrText)
            translatedText = response.targetText
            isTranslating = false
        } catch {
            // Apple couldn't do it (unsupported or undetected source language): fall back to Claude.
            await translateWithClaude(
                ocrText,
                targetID: targetLanguageID,
                appleReport: "Apple's translation failed: \(error.localizedDescription)"
            )
        }
    }

    private func translateWithClaude(_ text: String, targetID: String, appleReport: String) async {
        guard Prefs.apiKey != nil else {
            translationError = appleReport
                + "\n\nAdd an Anthropic API key in Settings to translate it with Claude instead."
            isTranslating = false
            return
        }
        let languageName = Locale(identifier: "en").localizedString(forIdentifier: targetID) ?? targetID
        do {
            translatedText = try await ClaudeClient.translate(text, to: languageName)
            translatedViaClaude = true
        } catch {
            translationError = "Couldn't translate: \(error.localizedDescription)"
        }
        isTranslating = false
    }

    func startClaude() {
        mode = .claude
        if turns.isEmpty {
            ask(Prefs.claudePrompt)
        }
    }

    func sendFollowUp() {
        let question = claudeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !claudeBusy else { return }
        claudeInput = ""
        ask(question)
    }

    private func ask(_ question: String) {
        guard Prefs.apiKey != nil else {
            claudeError = ClaudeError.noAPIKey.localizedDescription
            return
        }
        guard let base64 = imageBase64 else {
            claudeError = ClaudeError.badImage.localizedDescription
            return
        }
        claudeError = nil
        turns.append(ChatTurn(role: .user, text: question))
        claudeBusy = true
        let conversation = turns
        Task {
            do {
                let answer = try await ClaudeClient.send(imageBase64: base64, turns: conversation)
                turns.append(ChatTurn(role: .assistant, text: answer))
            } catch {
                claudeError = error.localizedDescription
                // Drop the unanswered question so the conversation stays valid.
                if turns.last?.role == .user { turns.removeLast() }
            }
            claudeBusy = false
        }
    }

    private func flash(_ message: String) {
        toast = message
        after(1.5) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }

    private func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }
}

// MARK: - View

struct ActionPanel: View {
    static let width: CGFloat = 460

    @ObservedObject var model: PanelModel
    @AppStorage(Prefs.targetLanguageKey) private var targetLanguage = Prefs.defaultTargetLanguage

    init(model: PanelModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            Divider()
            content
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .translationTask(model.translationConfig) { session in
            await model.translate(using: session)
        }
        .onChange(of: targetLanguage) { _, _ in
            if model.mode == .translate && model.hasText { model.restartTranslation() }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            PanelButton(title: "Copy text", icon: "doc.on.doc", active: model.mode == .text) {
                if model.mode == .text { model.copyText() } else { model.mode = .text }
            }
            .disabled(!model.ocrDone)

            PanelButton(title: "Translate", icon: "character.bubble", active: model.mode == .translate) {
                model.startTranslate()
            }
            .disabled(!model.ocrDone)

            PanelButton(title: "Lens", icon: "magnifyingglass", active: false) {
                model.searchLens()
            }

            PanelButton(title: "Ask Claude", icon: "sparkles", active: model.mode == .claude) {
                model.startClaude()
            }

            Spacer(minLength: 0)

            Button { model.copyImage() } label: { Image(systemName: "photo.on.rectangle") }
                .buttonStyle(.borderless)
                .help("Copy image")
            Button { model.close() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close (Esc)")
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .text: textContent
        case .translate: translateContent
        case .claude: claudeContent
        }
    }

    @ViewBuilder
    private var textContent: some View {
        if !model.ocrDone {
            ProgressView("Reading text…").controlSize(.small)
        } else if !model.hasText {
            Text("No text found. Try Lens or Ask Claude to search what's in the picture.")
                .foregroundStyle(.secondary)
        } else {
            AutoHeightScroll {
                Text(model.ocrText).textSelection(.enabled)
            }
            HStack {
                Text("Select part of it and press ⌘C, or:")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy all") { model.copyText() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var translateContent: some View {
        HStack {
            Text("Translate to").foregroundStyle(.secondary)
            LanguagePicker(selection: $targetLanguage)
                .frame(maxWidth: 200)
            Spacer()
        }
        if !model.hasText {
            Text("No text found to translate.").foregroundStyle(.secondary)
        } else if model.isTranslating {
            ProgressView("Translating…").controlSize(.small)
        } else if let error = model.translationError {
            Text(error).foregroundStyle(.red)
            if Prefs.apiKey == nil {
                Button("Open Settings") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
            }
        } else if !model.translatedText.isEmpty {
            AutoHeightScroll {
                Text(model.translatedText).textSelection(.enabled)
            }
            HStack {
                Text(model.translatedViaClaude ? "Translated by Claude"
                     : model.usedAppleIntelligence ? "Translated on-device · Apple Intelligence"
                     : "Translated on-device")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy translation") { model.copy(model.translatedText) }
            }
        }
    }

    @ViewBuilder
    private var claudeContent: some View {
        if !model.turns.isEmpty || model.claudeBusy {
            AutoHeightScroll(maxHeight: 300) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.turns) { turn in
                        if turn.role == .user {
                            Text(turn.text)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(markdown(turn.text)).textSelection(.enabled)
                        }
                    }
                    if model.claudeBusy {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        if let error = model.claudeError {
            HStack {
                Text(error).foregroundStyle(.red)
                if Prefs.apiKey == nil {
                    Button("Open Settings") {
                        NotificationCenter.default.post(name: .openSettings, object: nil)
                    }
                }
            }
        }
        HStack {
            TextField("Ask a follow-up…", text: $model.claudeInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.sendFollowUp() }
            Button { model.sendFollowUp() } label: { Image(systemName: "arrow.up.circle.fill") }
                .buttonStyle(.borderless)
                .disabled(model.claudeBusy)
            if let last = model.turns.last, last.role == .assistant {
                Button { model.copy(last.text) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy answer")
            }
        }
    }

    private func markdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }
}

// MARK: - Small components

struct PanelButton: View {
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Picker listing the languages Apple Translation supports on this Mac.
struct LanguagePicker: View {
    @Binding var selection: String
    @State private var languages: [(id: String, name: String)] = []

    init(selection: Binding<String>) {
        _selection = selection
    }

    var body: some View {
        Picker("", selection: $selection) {
            if !languages.contains(where: { $0.id == selection }) {
                Text(Self.displayName(selection)).tag(selection)
            }
            ForEach(languages, id: \.id) { lang in
                Text(lang.name).tag(lang.id)
            }
        }
        .labelsHidden()
        .task {
            let supported = await AppleTranslation.supportedLanguages()
            var seen = Set<String>()
            var list: [(id: String, name: String)] = []
            for language in supported {
                let id = language.minimalIdentifier
                if seen.insert(id).inserted {
                    list.append((id: id, name: Self.displayName(id)))
                }
            }
            // Languages Apple doesn't offer on this Mac are translated by Claude.
            for id in Self.claudeOnlyLanguages where seen.insert(id).inserted {
                list.append((id: id, name: Self.displayName(id) + " · Claude"))
            }
            languages = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    static let claudeOnlyLanguages = [
        "nb", "nn", "sv", "da", "fi", "is", "ur", "pa", "fa", "he", "el",
        "cs", "ro", "hu", "bg", "hr", "sk", "sl", "ms", "bn", "ta", "sw",
    ]

    static func displayName(_ id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }
}

/// A scroll view that is only as tall as its content, up to `maxHeight`.
struct AutoHeightScroll<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content
    @State private var contentHeight: CGFloat = 20

    init(maxHeight: CGFloat = 240, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .frame(height: min(max(contentHeight, 20), maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
