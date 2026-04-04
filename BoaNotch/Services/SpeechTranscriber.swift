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
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    cont.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
