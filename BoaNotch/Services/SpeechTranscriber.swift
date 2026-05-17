import Foundation
import Speech
import AppKit

class SpeechTranscriber {
    static func transcribe(audioURL: URL) async -> String? {
        // Wrap the TCC prompt with `withLoweredLevel` so the system permission
        // dialog renders above NotchPanel (`.mainMenu + 3`) instead of behind
        // it on first authorization. After auth is granted/denied the call
        // returns instantly and the lowering is effectively a no-op.
        let status = await NotchPanel.withLoweredLevel {
            await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status)
                }
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
