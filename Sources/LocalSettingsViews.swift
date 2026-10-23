// Settings rows for the local options: speech model download/remove and the Ollama server and model picker.
import SwiftUI

struct SpeechModelRow: View {
    let engine: SpeechEngine
    let whisperModel: WhisperModel
    let inputLocale: String

    @State private var installed = false
    @State private var progress: Double?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        LabeledContent("Model") {
            if busy {
                HStack {
                    ProgressView(value: progress).frame(width: 120)
                    Text(progress.map { "\(Int($0 * 100))%" } ?? "Loading…").monospacedDigit().foregroundStyle(.secondary)
                }
            } else if installed {
                HStack {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Remove") { remove() }
                }
            } else {
                Button("Download") { download() }
            }
        }
        .task(id: "\(engine.rawValue)-\(whisperModel.rawValue)") { installed = LocalSpeech.isInstalled(engine, whisper: whisperModel); error = nil }
        if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        if engine == .parakeet, !LocalSpeech.parakeetLanguages.contains(LocalSpeech.languageCode(inputLocale)) {
            Text("Parakeet does not support this language. Choose Whisper.").font(.caption).foregroundStyle(.orange)
        }
    }

    private func download() {
        busy = true
        progress = nil
        error = nil
        Task { @MainActor in
            do {
                try await LocalSpeech.shared.prepare(engine) { p in Task { @MainActor in progress = p } }
            } catch {
                self.error = error.localizedDescription
            }
            installed = LocalSpeech.isInstalled(engine, whisper: whisperModel)
            busy = false
        }
    }

    private func remove() {
        Task { @MainActor in
            await LocalSpeech.shared.unload(engine)
            LocalSpeech.remove(engine, whisper: whisperModel)
            installed = LocalSpeech.isInstalled(engine, whisper: whisperModel)
        }
    }
}

struct OllamaSection: View {
    @Binding var url: String
    @Binding var model: String

    @State private var models: [OllamaModel] = []
    @State private var reachable: Bool?
    @State private var pulling: String?
    @State private var pullProgress: Double?
    @State private var pullStatus = ""
    @State private var pullTask: Task<Void, Never>?
    @State private var error: String?
    @State private var custom = ""

    private var chatModels: [OllamaModel] { models.filter(\.canChat) }
    private var missingRecommended: [(name: String, note: String)] {
        Ollama.recommended.filter { !Ollama.isInstalled($0.name, in: models) }
    }

    var body: some View {
        TextField("Server", text: $url, prompt: Text(Ollama.defaultURL))
            .onSubmit { Task { await refresh() } }
        if reachable == false {
            Text("Ollama is not running at this address. Start the Ollama app, then check again.").font(.caption).foregroundStyle(.orange)
            HStack {
                Button("Check again") { Task { await refresh() } }
                Link("Get Ollama", destination: Ollama.downloadPage).font(.caption)
            }
        } else if reachable == true {
            Picker("Model", selection: $model) {
                if !chatModels.contains(where: { $0.name == model }) { Text("\(model) (not installed)").tag(model) }
                ForEach(chatModels) { Text($0.name).tag($0.name) }
            }
            if let pulling {
                HStack {
                    ProgressView(value: pullProgress).frame(maxWidth: .infinity)
                    Text(pullProgress.map { "\(Int($0 * 100))%" } ?? pullStatus).monospacedDigit().foregroundStyle(.secondary)
                    Button("Cancel") { pullTask?.cancel() }
                }
                Text("Downloading \(pulling)").font(.caption).foregroundStyle(.secondary)
            } else {
                if !missingRecommended.isEmpty {
                    Menu("Download a recommended model") {
                        ForEach(missingRecommended, id: \.name) { item in
                            Button("\(item.name) – \(item.note)") { startPull(item.name) }
                        }
                    }
                }
                HStack {
                    TextField("Other model", text: $custom, prompt: Text("name from ollama.com/library"))
                    Button("Download") { startPull(custom.trimmingCharacters(in: .whitespaces)) }
                        .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        Color.clear.frame(height: 0).task { await refresh() }
    }

    // Ollama calls read the saved URL, so keep it in step with the field.
    private func refresh() async {
        Settings.ollamaURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            models = try await Ollama.installedModels()
            reachable = true
            error = nil
        } catch {
            reachable = false
        }
    }

    private func startPull(_ name: String) {
        guard !name.isEmpty else { return }
        pulling = name
        pullProgress = nil
        pullStatus = "Starting…"
        error = nil
        pullTask = Task { @MainActor in
            do {
                try await Ollama.pull(name) { fraction, status in
                    Task { @MainActor in pullProgress = fraction; pullStatus = status }
                }
                model = name
                custom = ""
            } catch is CancellationError {
            } catch let urlError as URLError where urlError.code == .cancelled {
            } catch {
                self.error = error.localizedDescription
            }
            pulling = nil
            await refresh()
        }
    }
}
