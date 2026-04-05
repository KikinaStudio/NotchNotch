import AVFoundation
import Foundation

class AudioRecorder: ObservableObject {
    @Published var isRecording = false

    private var audioRecorder: AVAudioRecorder?
    private var outputURL: URL?

    private var cacheDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".hermes/cache/audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func startRecording() {
        let filename = "voice_\(UUID().uuidString.prefix(8)).m4a"
        let url = cacheDir.appendingPathComponent(filename)
        outputURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("[notchnotch] Recording error: \(error)")
        }
    }

    func stopRecording() -> URL? {
        cleanup()
        return outputURL
    }

    private func cleanup() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
    }
}
