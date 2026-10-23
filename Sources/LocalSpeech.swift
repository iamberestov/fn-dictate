// Local speech-to-text: Whisper (WhisperKit) and Parakeet (FluidAudio), both Core ML on the Neural Engine.
import AVFoundation
import FluidAudio
import Foundation
import WhisperKit

enum SpeechEngine: String, CaseIterable, Identifiable {
    case apple, whisper, parakeet
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple – built in (Russian goes to Apple servers)"
        case .whisper: "Whisper – on this Mac (best quality)"
        case .parakeet: "Parakeet – on this Mac (fastest)"
        }
    }

    var isLocal: Bool { self != .apple }
}

enum WhisperModel: String, CaseIterable, Identifiable {
    case turbo = "large-v3-v20240930_turbo"
    case compact = "large-v3-v20240930_626MB"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .turbo: "Large v3 Turbo (faster, about 1.6 GB)"
        case .compact: "Large v3 compact (about 0.6 GB)"
        }
    }
}

// MARK: - Silence gate

// Whisper writes phrases like "Продолжение следует..." for silence, so near-silent recordings never reach it.
// Measured on real clips: speech peaks above -20 dBFS and has 40%+ of 30 ms frames above -45 dBFS;
// a silent press peaks near -41 dBFS with no frame above -45 dBFS.
enum SilenceGate {
    static func hasSpeech(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData?[0]
        else { return true } // cannot measure: let the engine decide
        let count = Int(buffer.frameLength)
        let frame = max(1, Int(file.processingFormat.sampleRate * 0.03))
        var peak: Float = 0
        var loud = 0, frames = 0
        var start = 0
        while start + frame <= count {
            var sum: Float = 0
            for i in start..<start + frame { let v = channel[i]; sum += v * v; peak = max(peak, abs(v)) }
            if 20 * log10(max(sqrt(sum / Float(frame)), 1e-6)) > -45 { loud += 1 }
            frames += 1
            start += frame
        }
        guard frames > 0 else { return false }
        let peakDB = 20 * log10(max(peak, 1e-6))
        logLine("fn-dictate: audio peak \(Int(peakDB)) dBFS, \(loud * 100 / frames)% of frames above -45 dBFS")
        return peakDB > -38 && Double(loud) / Double(frames) >= 0.03
    }

    // Subtitle credits Whisper learned from video data. Only whole-text matches are dropped, so real sentences stay.
    private static let artifacts: Set<String> = [
        "продолжение следует", "спасибо за просмотр", "спасибо за внимание", "thanks for watching",
        "thank you for watching", "subtitles by the amara.org community",
    ]

    static func isArtifact(_ text: String) -> Bool {
        let normalized = text.lowercased().filter { $0.isLetter || $0.isWhitespace }
            .split(separator: " ").joined(separator: " ")
        return normalized.isEmpty || artifacts.contains(normalized)
    }
}

// MARK: - Engines

actor LocalSpeech {
    static let shared = LocalSpeech()

    // Parakeet v3 languages (ISO 639-1).
    static let parakeetLanguages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt",
        "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FnDictate/models", isDirectory: true)
    }

    // "ru-RU" -> "ru"
    static func languageCode(_ locale: String) -> String {
        locale.split(separator: "-").first.map(String.init)?.lowercased() ?? locale
    }

    private var whisper: WhisperKit?
    private var whisperLoaded: String?
    private var parakeet: AsrManager?

    // MARK: Installed state (no loading, cheap enough for the Settings window)

    nonisolated static func isInstalled(_ engine: SpeechEngine, whisper model: WhisperModel = Settings.whisperModel) -> Bool {
        switch engine {
        case .apple: return true
        case .whisper:
            let repo = modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: repo.path)) ?? []
            return entries.contains { $0.hasSuffix(model.rawValue) }
        case .parakeet:
            return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
        }
    }

    nonisolated static func remove(_ engine: SpeechEngine, whisper model: WhisperModel = Settings.whisperModel) {
        switch engine {
        case .apple: break
        case .whisper:
            let repo = modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: repo.path)) ?? [] where entry.hasSuffix(model.rawValue) {
                try? FileManager.default.removeItem(at: repo.appendingPathComponent(entry))
            }
        case .parakeet:
            try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: .v3))
        }
    }

    // MARK: Loading

    // Downloads the model if needed (progress 0...1) and loads it. Safe to call repeatedly.
    func prepare(_ engine: SpeechEngine, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        switch engine {
        case .apple: return
        case .whisper:
            let name = Settings.whisperModel.rawValue
            if whisper != nil, whisperLoaded == name { return }
            let base = Self.modelsDirectory
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let folder = try await WhisperKit.download(variant: name, downloadBase: base, progressCallback: { progress($0.fractionCompleted) })
            whisper = nil
            whisper = try await WhisperKit(WhisperKitConfig(downloadBase: base, modelFolder: folder.path, verbose: false, download: false))
            whisperLoaded = name
            logLine("fn-dictate: Whisper \(name) loaded")
        case .parakeet:
            if parakeet != nil { return }
            let models = try await AsrModels.downloadAndLoad(version: .v3, progressHandler: { progress($0.fractionCompleted) })
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            parakeet = manager
            logLine("fn-dictate: Parakeet v3 loaded")
        }
    }

    func isLoaded(_ engine: SpeechEngine) -> Bool {
        switch engine {
        case .apple: true
        case .whisper: whisper != nil && whisperLoaded == Settings.whisperModel.rawValue
        case .parakeet: parakeet != nil
        }
    }

    func unload(_ engine: SpeechEngine) {
        switch engine {
        case .apple: break
        case .whisper: whisper = nil; whisperLoaded = nil
        case .parakeet: parakeet = nil
        }
    }

    // MARK: Transcription

    func transcribe(_ url: URL, engine: SpeechEngine, locale: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> String {
        let language = Self.languageCode(locale)
        guard SilenceGate.hasSpeech(url) else {
            logLine("fn-dictate: silence gate: no speech in the recording")
            return ""
        }
        try await prepare(engine, progress: progress)
        let text: String
        switch engine {
        case .apple:
            return ""
        case .whisper:
            let options = DecodingOptions(task: .transcribe, language: language, detectLanguage: false)
            let results = try await whisper!.transcribe(audioPath: url.path, decodeOptions: options)
            text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        case .parakeet:
            guard Self.parakeetLanguages.contains(language) else {
                throw NSError(domain: "fn-dictate", code: 3, userInfo: [NSLocalizedDescriptionKey: "Parakeet does not support \(language); choose Whisper in Settings"])
            }
            var state = TdtDecoderState.make()
            let result = try await parakeet!.transcribe(url, decoderState: &state, language: nil)
            text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if SilenceGate.isArtifact(text) {
            logLine("fn-dictate: dropped likely hallucination: \(text)")
            return ""
        }
        return text
    }
}
