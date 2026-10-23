import AppKit
import AVFoundation
import Security
import SwiftUI

// MARK: - Provider (who turns the raw transcript into the pasted text)

enum Provider: String, CaseIterable, Identifiable {
    case claudeAPI, openAIAPI, claudeCLI, codexCLI, ollama
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeAPI: "Claude – API key"
        case .openAIAPI: "OpenAI / Codex – API key"
        case .claudeCLI: "Claude Code CLI (signed in, no key)"
        case .codexCLI: "Codex CLI (signed in, no key)"
        case .ollama: "Ollama – on this Mac (no key)"
        }
    }

    var keyAccount: String? {
        switch self {
        case .claudeAPI: "anthropic"
        case .openAIAPI: "openai"
        case .claudeCLI, .codexCLI, .ollama: nil
        }
    }

    var keyEnvironment: String? {
        switch self {
        case .claudeAPI: "ANTHROPIC_API_KEY"
        case .openAIAPI: "OPENAI_API_KEY"
        case .claudeCLI, .codexCLI, .ollama: nil
        }
    }

    var keyURL: URL? {
        switch self {
        case .claudeAPI: URL(string: "https://console.anthropic.com/settings/keys")
        case .openAIAPI: URL(string: "https://platform.openai.com/api-keys")
        case .claudeCLI, .codexCLI, .ollama: nil
        }
    }

    var cliName: String? {
        switch self {
        case .claudeCLI: "claude"
        case .codexCLI: "codex"
        case .claudeAPI, .openAIAPI, .ollama: nil
        }
    }

    // Empty means "the CLI's own default model".
    var defaultModel: String {
        switch self {
        case .claudeAPI: "claude-haiku-5-5"
        case .openAIAPI: "gpt-5-mini"
        case .claudeCLI: "haiku"
        case .codexCLI: ""
        case .ollama: Ollama.recommended[0].name
        }
    }
}

// MARK: - Settings (UserDefaults; API keys live in the Keychain)

enum Settings {
    static let d = UserDefaults.standard
    static let sameAsSpoken = "Same as spoken"

    static var provider: Provider? {
        get { d.string(forKey: "provider").flatMap(Provider.init(rawValue:)) }
        set { d.set(newValue?.rawValue, forKey: "provider") }
    }
    static func model(for p: Provider) -> String { d.string(forKey: "model.\(p.rawValue)") ?? p.defaultModel }
    static func setModel(_ m: String, for p: Provider) { d.set(m, forKey: "model.\(p.rawValue)") }

    static func apiKey(for p: Provider) -> String? {
        if let env = p.keyEnvironment, let v = ProcessInfo.processInfo.environment[env], !v.isEmpty { return v }
        return p.keyAccount.flatMap(Keychain.get)
    }

    // Existing users (a provider is already chosen) keep Apple speech after an update; new installs start on Whisper.
    static var speechEngine: SpeechEngine {
        get { d.string(forKey: "speechEngine").flatMap(SpeechEngine.init(rawValue:)) ?? (provider == nil ? .whisper : .apple) }
        set { d.set(newValue.rawValue, forKey: "speechEngine") }
    }
    static var whisperModel: WhisperModel {
        get { d.string(forKey: "whisperModel").flatMap(WhisperModel.init(rawValue:)) ?? .turbo }
        set { d.set(newValue.rawValue, forKey: "whisperModel") }
    }
    static var ollamaURL: String {
        get { d.string(forKey: "ollamaURL") ?? Ollama.defaultURL }
        set { d.set(newValue, forKey: "ollamaURL") }
    }

    static var inputLocale: String {
        get { d.string(forKey: "inputLocale") ?? "ru-RU" }
        set { d.set(newValue, forKey: "inputLocale") }
    }
    static var outputLanguage: String {
        get { d.string(forKey: "outputLanguage") ?? "English (US)" }
        set { d.set(newValue, forKey: "outputLanguage") }
    }
    static var preferBuiltInMic: Bool {
        get { d.object(forKey: "preferBuiltInMic") as? Bool ?? true }
        set { d.set(newValue, forKey: "preferBuiltInMic") }
    }
    static var debugLog: Bool {
        get { d.bool(forKey: "debugLog") }
        set { d.set(newValue, forKey: "debugLog") }
    }
    static var minHold: Double { d.object(forKey: "minHoldSeconds") as? Double ?? 0.3 }

    static let inputLocales: [(id: String, name: String)] = [
        ("ru-RU", "Russian"), ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("uk-UA", "Ukrainian"),
        ("de-DE", "German"), ("fr-FR", "French"), ("es-ES", "Spanish"), ("it-IT", "Italian"),
        ("pt-BR", "Portuguese (Brazil)"), ("pl-PL", "Polish"), ("tr-TR", "Turkish"), ("zh-CN", "Chinese (Mandarin)"),
        ("ja-JP", "Japanese"), ("ko-KR", "Korean"),
    ]
    static let outputLanguages = [
        "English (US)", "English (UK)", "Russian", "Ukrainian", "German", "French", "Spanish", "Italian",
        "Portuguese (Brazil)", "Polish", "Turkish", "Chinese (Simplified)", "Japanese", "Korean", sameAsSpoken,
    ]
}

// MARK: - Keychain

enum Keychain {
    private static let service = "FnDictate"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - CLI lookup (GUI apps don't inherit the shell PATH, so ask a login shell)

enum CLI {
    private static var cache: [String: String] = [:]

    static func path(_ name: String) -> String? {
        if let p = cache[name] { return p }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v \(name)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let found = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        guard p.terminationStatus == 0, let found, found.hasPrefix("/") else { return nil }
        cache[name] = found
        return found
    }

    // Runs through a login shell so node-based CLIs find their interpreter on the user's PATH.
    static func run(_ executable: String, _ args: [String], stdin: String) async throws -> (status: Int32, out: String, err: String) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", "exec \"$0\" \"$@\"", executable] + args
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
            p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
            final class Output: @unchecked Sendable { var out = Data(), err = Data() }
            let collected = Output()
            let group = DispatchGroup()
            for (pipe, isOut) in [(outPipe, true), (errPipe, false)] {
                group.enter()
                DispatchQueue.global().async {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if isOut { collected.out = data } else { collected.err = data }
                    group.leave()
                }
            }
            p.terminationHandler = { proc in
                group.notify(queue: .global()) {
                    cont.resume(returning: (proc.terminationStatus, String(decoding: collected.out, as: UTF8.self), String(decoding: collected.err, as: UTF8.self)))
                }
            }
            do {
                try p.run()
                inPipe.fileHandleForWriting.write(Data(stdin.utf8))
                try? inPipe.fileHandleForWriting.close()
            } catch { cont.resume(throwing: error) }
        }
    }
}

// MARK: - Settings window

struct SettingsView: View {
    var onSaved: () -> Void

    @State private var provider: Provider = Settings.provider ?? (CLI.path("claude") != nil ? .claudeCLI : .claudeAPI)
    @State private var apiKey = ""
    @State private var model = ""
    @State private var speechEngine = Settings.speechEngine
    @State private var whisperModel = Settings.whisperModel
    @State private var ollamaURL = Settings.ollamaURL
    @State private var inputLocale = Settings.inputLocale
    @State private var outputLanguage = Settings.outputLanguage
    @State private var preferBuiltInMic = Settings.preferBuiltInMic
    @State private var debugLog = Settings.debugLog
    @State private var testResult: String?
    @State private var testing = false
    @State private var permissionsTick = 0

    var body: some View {
        Form {
            Section("Text processing") {
                Picker("Provider", selection: $provider) {
                    ForEach(Provider.allCases) { Text($0.title).tag($0) }
                }
                if provider.keyAccount != nil {
                    SecureField("API key", text: $apiKey, prompt: Text("Paste your key"))
                    if let url = provider.keyURL { Link("Get a key", destination: url).font(.caption) }
                } else if let name = provider.cliName {
                    LabeledContent("CLI") {
                        Text(CLI.path(name) ?? "“\(name)” not found – install it and sign in").foregroundStyle(.secondary)
                    }
                }
                if provider == .ollama {
                    OllamaSection(url: $ollamaURL, model: $model)
                } else {
                    TextField("Model", text: $model, prompt: Text(provider.defaultModel.isEmpty ? "CLI default" : provider.defaultModel))
                }
            }
            Section("Speech") {
                Picker("Speech to text", selection: $speechEngine) {
                    ForEach(SpeechEngine.allCases) { Text($0.title).tag($0) }
                }
                if speechEngine == .whisper {
                    Picker("Whisper model", selection: $whisperModel) {
                        ForEach(WhisperModel.allCases) { Text($0.title).tag($0) }
                    }
                }
                if speechEngine.isLocal {
                    SpeechModelRow(engine: speechEngine, whisperModel: whisperModel, inputLocale: inputLocale)
                }
                if speechEngine.isLocal && provider == .ollama {
                    Label("Everything stays on this Mac", systemImage: "lock.fill").foregroundStyle(.green).font(.callout)
                }
                Picker("I speak", selection: $inputLocale) {
                    ForEach(Settings.inputLocales, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("Paste as", selection: $outputLanguage) {
                    ForEach(Settings.outputLanguages, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Use the Mac's built-in microphone", isOn: $preferBuiltInMic)
            }
            Section("Permissions") {
                let _ = permissionsTick
                permissionRow("Accessibility (to paste)", AXIsProcessTrusted(), "Privacy_Accessibility")
                permissionRow("Input Monitoring (to hear Fn)", CGPreflightListenEventAccess(), "Privacy_ListenEvent")
                permissionRow("Microphone", AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "Privacy_Microphone")
            }
            Section {
                Toggle("Write a debug log to ~/Library/Logs/FnDictate.log", isOn: $debugLog)
            }
            Section {
                HStack {
                    Button(testing ? "Testing…" : "Test") { test() }.disabled(testing)
                    Spacer()
                    Button("Save") { save(); onSaved() }.keyboardShortcut(.defaultAction)
                }
                if let testResult { Text(testResult).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        // Taller than the screen scrolls instead of running off it.
        .frame(maxHeight: (NSScreen.main?.visibleFrame.height ?? 800) - 80)        .onAppear { load() }
        .onChange(of: provider) { load() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in permissionsTick += 1 }
    }

    private func permissionRow(_ title: String, _ granted: Bool, _ pane: String) -> some View {
        LabeledContent(title) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
    }

    private func load() {
        apiKey = provider.keyAccount.flatMap(Keychain.get) ?? ""
        model = Settings.d.string(forKey: "model.\(provider.rawValue)") ?? ""
        if provider == .ollama && model.isEmpty { model = provider.defaultModel }
    }

    private func save() {
        Settings.provider = provider
        if let account = provider.keyAccount { Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: account) }
        if model.isEmpty { Settings.d.removeObject(forKey: "model.\(provider.rawValue)") } else { Settings.setModel(model, for: provider) }
        Settings.speechEngine = speechEngine
        Settings.whisperModel = whisperModel
        Settings.ollamaURL = ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.inputLocale = inputLocale
        Settings.outputLanguage = outputLanguage
        Settings.preferBuiltInMic = preferBuiltInMic
        Settings.debugLog = debugLog
    }

    private func test() {
        save()
        testing = true
        testResult = nil
        Task { @MainActor in
            do {
                let sample = "ну короче это э-э проверка диктовки, всё работает"
                testResult = "✓ " + (try await Polisher.polish(sample))
            } catch {
                testResult = "✗ " + error.localizedDescription
            }
            testing = false
        }
    }
}

final class SettingsWindow {
    private var window: NSWindow?
    var onSaved: () -> Void = {}

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView { [weak self] in
                self?.onSaved()
                self?.window?.close()
            })
            // Without this the window can open with zero content height (preferredContentSize stays 0x0).
            host.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: host)
            w.setContentSize(host.view.fittingSize)
            w.title = "FnDictate Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)    }
}
