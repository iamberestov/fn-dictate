// Throwaway test tool: records the default microphone to a 16 kHz mono WAV until a line arrives on stdin.
// Usage: record <out.wav>
import AVFoundation
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: record <out.wav>\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])

let sema = DispatchSemaphore(value: 0)
var granted = false
AVCaptureDevice.requestAccess(for: .audio) { granted = $0; sema.signal() }
sema.wait()
guard granted else {
    FileHandle.standardError.write(Data("microphone access denied: allow it for your terminal in System Settings > Privacy > Microphone\n".utf8))
    exit(3)
}

let settings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: 16000,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
]
let recorder = try AVAudioRecorder(url: url, settings: settings)
guard recorder.record() else {
    FileHandle.standardError.write(Data("could not start recording\n".utf8))
    exit(4)
}
print("recording", terminator: "\n")
fflush(stdout)
_ = readLine()
recorder.stop()
print("saved \(url.path)")
