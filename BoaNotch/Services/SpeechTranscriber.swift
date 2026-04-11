import Foundation
import Speech

class SpeechTranscriber {
    static func transcribe(audioURL: URL) async -> String? {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard status == .authorized else {
            print("[notchnotch] Speech auth denied: \(status.rawValue)")
            return nil
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
                ?? SFSpeechRecognizer(locale: Locale.current)
                ?? SFSpeechRecognizer() else {
            print("[notchnotch] No speech recognizer available for any locale")
            return nil
        }

        guard recognizer.isAvailable else {
            print("[notchnotch] Speech recognizer not available (locale: \(recognizer.locale))")
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let result, result.isFinal {
                    resumed = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    resumed = true
                    print("[notchnotch] Speech recognition error: \(error.localizedDescription)")
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
