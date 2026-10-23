// Local LLM through an Ollama server: list models, pull with progress, chat.
import Foundation

struct OllamaModel: Identifiable, Hashable {
    let name: String
    let size: Int64
    let canChat: Bool
    var id: String { name }
}

enum Ollama {
    static let defaultURL = "http://localhost:11434"
    static let downloadPage = URL(string: "https://ollama.com/download")!

    // Default first; sizes are the download sizes shown next to "Download".
    static let recommended: [(name: String, note: String)] = [
        ("qwen3:8b", "best quality for its speed, about 5.2 GB"),
        ("qwen3.5:4b", "lighter, about 3.3 GB"),
        ("gemma4:e4b", "good at translation, about 6.6 GB"),
    ]

    static var baseURL: URL { URL(string: Settings.ollamaURL) ?? URL(string: defaultURL)! }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "fn-dictate", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func request(_ path: String, body: [String: Any]? = nil, timeout: TimeInterval = 30) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private static func unreachable(_ error: Error) -> NSError {
        (error as? URLError).map { _ in failure("Ollama is not running at \(baseURL.absoluteString) – start the Ollama app") } ?? (error as NSError)
    }

    static func installedModels() async throws -> [OllamaModel] {
        do {
            let (data, response) = try await URLSession.shared.data(for: request("api/tags", timeout: 3))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]]
            else { throw failure("Unexpected reply from Ollama") }
            return models.compactMap { m in
                guard let name = m["name"] as? String else { return nil }
                let caps = m["capabilities"] as? [String] ?? ["completion"]
                return OllamaModel(name: name, size: (m["size"] as? NSNumber)?.int64Value ?? 0, canChat: caps.contains("completion"))
            }
        } catch { throw unreachable(error) }
    }

    static func isInstalled(_ name: String, in models: [OllamaModel]) -> Bool {
        models.contains { $0.name == name || ($0.name.hasSuffix(":latest") && $0.name.dropLast(7) == name) }
    }

    // One chat turn. `think: false` keeps reasoning models from spending tokens on a thinking phase;
    // models without thinking support reject the field, so retry without it.
    static func chat(model: String, system: String, user: String) async throws -> String {
        func send(noThinking: Bool) async throws -> (json: [String: Any], status: Int, raw: Data) {
            var body: [String: Any] = [
                "model": model, "stream": false, "keep_alive": "30m", "options": ["temperature": 0.2],
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            ]
            if noThinking { body["think"] = false }
            let (data, response) = try await URLSession.shared.data(for: request("api/chat", body: body, timeout: 120))
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            return (json, (response as? HTTPURLResponse)?.statusCode ?? 0, data)
        }
        do {
            var reply = try await send(noThinking: true)
            if reply.status == 400, (reply.json["error"] as? String)?.contains("think") == true {
                reply = try await send(noThinking: false)
            }
            guard reply.status == 200 else {
                let message = reply.json["error"] as? String ?? String(decoding: reply.raw, as: UTF8.self)
                throw failure(message.contains("not found") ? "Model \(model) is not installed – download it in Settings" : message)
            }
            guard let text = (reply.json["message"] as? [String: Any])?["content"] as? String else { throw failure("Unexpected reply from Ollama") }
            return text
        } catch { throw unreachable(error) }
    }

    // Streams `POST /api/pull`; progress is 0...1 (nil while the server prepares). Cancel by cancelling the task.
    static func pull(_ model: String, progress: @escaping @Sendable (Double?, String) -> Void) async throws {
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request("api/pull", body: ["model": model, "stream": true], timeout: 3600))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure("Ollama refused to pull \(model)") }
            for try await line in bytes.lines {
                guard let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                if let error = json["error"] as? String { throw failure(error) }
                let status = json["status"] as? String ?? ""
                let total = (json["total"] as? NSNumber)?.doubleValue ?? 0
                let done = (json["completed"] as? NSNumber)?.doubleValue ?? 0
                progress(total > 0 ? done / total : nil, status)
            }
        } catch { throw unreachable(error) }
    }
}
