import Foundation
import Speech

class SpeechTranscriber {
    static func transcribe(audioURL: URL) async -> String? {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard status == .authorized else { return nil }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
                ?? SFSpeechRecognizer(locale: Locale.current)
                ?? SFSpeechRecognizer() else { return nil }

        guard recognizer.isAvailable else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let result, result.isFinal {
                    resumed = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    resumed = true
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
