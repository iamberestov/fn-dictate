// Usage: stt-bench <apple|parakeet|parakeet-hint|whisper> [--model <whisper model>] < lines of "<wav path>\t<lang>"
// Prints one JSON object per line: {"event":"load",...} then {"event":"clip",...} for each input line.
import AVFoundation
import FluidAudio
import Foundation
import Speech
import WhisperKit

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

func residentMB() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : -1
}

// MARK: - Engines

protocol Engine {
    func transcribe(_ url: URL, lang: String) async throws -> String
}

let appleLocales = ["ru": "ru-RU", "en": "en-US", "uk": "uk-UA", "de": "de-DE", "fr": "fr-FR", "es": "es-ES"]

// Same path as Transcriber in the app: on-device SpeechAnalyzer first, server dictation when no on-device model.
struct AppleEngine: Engine {
    func transcribe(_ url: URL, lang: String) async throws -> String {
        let wanted = Locale(identifier: appleLocales[lang] ?? lang)
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) {
            do {
                let t = SpeechTranscriber(locale: locale, preset: .transcription)
                return try await run(url, module: t, results: t.results.map { String($0.text.characters) })
            } catch {
                FileHandle.standardError.write(Data("apple on-device \(locale.identifier) failed, using server: \(error.localizedDescription)\n".utf8))
            }
        }
        return try await serverRecognize(url, locale: wanted)
    }

    private func serverRecognize(_ url: URL, locale: Locale) async throws -> String {
        // From a terminal the permission request aborts the process (the terminal has no Speech usage description),
        // so only use server dictation when access was already granted.
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw NSError(domain: "stt-bench", code: 2, userInfo: [NSLocalizedDescriptionKey: "no on-device \(locale.identifier) model and server dictation not authorized for this process"])
        }
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized, let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw NSError(domain: "stt-bench", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition for \(locale.identifier) unavailable (status \(status.rawValue))"])
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.addsPunctuation = true
        request.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { c in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let result, result.isFinal { done = true; c.resume(returning: result.bestTranscription.formattedString) }
                else if let error { done = true; c.resume(throwing: error) }
            }
        }
    }

    private func run<S: AsyncSequence>(_ url: URL, module: any SpeechModule, results: S) async throws -> String where S.Element == String {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        let collector = Task {
            var text = ""
            for try await chunk in results { text += chunk }
            return text
        }
        let audio = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: audio) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// useHint: pass the spoken language so v3 skips tokens of the wrong script (e.g. Latin letters in Russian speech).
final class ParakeetEngine: Engine {
    private let manager = AsrManager(config: .default)
    private let useHint: Bool
    init(useHint: Bool) { self.useHint = useHint }

    func load() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        try await manager.loadModels(models)
    }

    func transcribe(_ url: URL, lang: String) async throws -> String {
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(url, decoderState: &state, language: useHint ? Language(rawValue: lang) : nil)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class WhisperEngine: Engine {
    private var pipe: WhisperKit?
    let model: String
    init(model: String) { self.model = model }

    func load() async throws {
        pipe = try await WhisperKit(WhisperKitConfig(model: model))
    }

    func transcribe(_ url: URL, lang: String) async throws -> String {
        let options = DecodingOptions(task: .transcribe, language: lang == "auto" ? nil : lang, detectLanguage: lang == "auto")
        let results = try await pipe!.transcribe(audioPath: url.path, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: stt-bench <apple|parakeet|whisper> [--model <name>]\n".utf8))
    exit(2)
}
var whisperModel = "large-v3-v20240930_626MB"
if let i = args.firstIndex(of: "--model"), i + 1 < args.count { whisperModel = args[i + 1] }

let loadStart = Date()
let engine: Engine
do {
    switch args[1] {
    case "apple": engine = AppleEngine()
    case "parakeet": let e = ParakeetEngine(useHint: false); try await e.load(); engine = e
    case "parakeet-hint": let e = ParakeetEngine(useHint: true); try await e.load(); engine = e
    case "whisper": let e = WhisperEngine(model: whisperModel); try await e.load(); engine = e
    default: FileHandle.standardError.write(Data("unknown engine \(args[1])\n".utf8)); exit(2)
    }
} catch {
    emit(["event": "load", "engine": args[1], "error": "\(error)"])
    exit(1)
}
emit(["event": "load", "engine": args[1], "loadMs": ms(since: loadStart), "residentMB": residentMB()])

var lines: [(URL, String)] = []
while let line = readLine() {
    let parts = line.split(separator: "\t").map(String.init)
    if parts.count == 2 { lines.append((URL(fileURLWithPath: parts[0]), parts[1])) }
}

// Warm-up: the first transcription pays for compiling/loading on-device kernels; report it separately.
if let first = lines.first {
    let start = Date()
    _ = try? await engine.transcribe(first.0, lang: first.1)
    emit(["event": "warmup", "engine": args[1], "ms": ms(since: start), "residentMB": residentMB()])
}

for (url, lang) in lines {
    let start = Date()
    do {
        let text = try await engine.transcribe(url, lang: lang)
        emit(["event": "clip", "engine": args[1], "file": url.lastPathComponent, "ms": ms(since: start), "text": text])
    } catch {
        emit(["event": "clip", "engine": args[1], "file": url.lastPathComponent, "ms": ms(since: start), "error": "\(error)"])
    }
}
emit(["event": "done", "engine": args[1], "residentMB": residentMB()])
