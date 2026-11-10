import AppKit
import Vision

// MARK: - Text recognition (on-device, Apple Vision)

enum TextRecognizer {
    static func recognize(_ image: CGImage) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return ""
            }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}

// MARK: - Google Lens

enum LensSearch {
    /// Opens the image in Google Lens in your default browser.
    /// Writes a tiny local page that uploads the image to Lens's web upload form,
    /// so the search runs in your own browser session.
    static func open(_ image: CGImage) {
        guard let png = image.scaled(maxDimension: 2000).pngData() else { return }
        let base64 = png.base64EncodedString()
        let ts = Int(Date().timeIntervalSince1970 * 1000)

        let html = """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>Google Lens…</title></head>
        <body style="font-family:-apple-system,sans-serif;padding:48px;color:#666">
        Sending to Google Lens…
        <form id="f" method="POST" enctype="multipart/form-data"
              action="https://lens.google.com/v3/upload?ep=ccm&st=\(ts)">
          <input type="file" name="encoded_image" id="img" hidden>
        </form>
        <script>
          const bin = atob("\(base64)");
          const bytes = new Uint8Array(bin.length);
          for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
          const dt = new DataTransfer();
          dt.items.add(new File([bytes], "image.png", { type: "image/png" }));
          document.getElementById("img").files = dt.files;
          document.getElementById("f").submit();
        </script>
        </body></html>
        """

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("CircleSearch", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        cleanOldFiles(in: dir)
        let file = dir.appendingPathComponent("lens-\(ts).html")
        do {
            try html.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return
        }

        // Open with the default *browser* (a plain .html might open in a code editor).
        if let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://www.google.com")!) {
            NSWorkspace.shared.open([file], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(file)
        }
    }

    private static func cleanOldFiles(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-120)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: file) }
        }
    }
}

// MARK: - Claude (Anthropic Messages API)

struct ChatTurn: Identifiable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

enum ClaudeError: LocalizedError {
    case noAPIKey
    case badImage
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Add your Anthropic API key in Settings."
        case .badImage: return "Couldn't encode the image."
        case .api(let message): return message
        }
    }
}

enum ClaudeClient {
    private static let systemPrompt = """
    The user circled part of their Mac screen and is asking about it. \
    The image is that circled area. Answer concisely and directly. \
    Use short Markdown (bold, lists) only when it helps.
    """

    /// Text translation, used when Apple Translation doesn't support the language.
    static func translate(_ text: String, to languageName: String) async throws -> String {
        let system = """
        You are a translator. Translate the user's text into \(languageName). \
        Keep the line breaks and formatting. Reply with only the translation, nothing else.
        """
        return try await post(system: system, messages: [["role": "user", "content": text]])
    }

    /// Sends the whole conversation; the image is attached to the first user turn.
    static func send(imageBase64: String, turns: [ChatTurn]) async throws -> String {
        var messages: [[String: Any]] = []
        for (index, turn) in turns.enumerated() {
            if index == 0 {
                messages.append([
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": ["type": "base64", "media_type": "image/png", "data": imageBase64],
                        ],
                        ["type": "text", "text": turn.text],
                    ] as [[String: Any]],
                ])
            } else {
                messages.append(["role": turn.role.rawValue, "content": turn.text])
            }
        }
        return try await post(system: systemPrompt, messages: messages)
    }

    private static func post(system: String, messages: [[String: Any]]) async throws -> String {
        guard let apiKey = Prefs.apiKey else { throw ClaudeError.noAPIKey }

        let body: [String: Any] = [
            "model": Prefs.claudeModel,
            "max_tokens": 2048,
            "system": system,
            "messages": messages,
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw ClaudeError.api(message ?? "Request failed (HTTP \(http.statusCode)).")
        }

        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
        return text.isEmpty ? "(No answer)" : text
    }
}
