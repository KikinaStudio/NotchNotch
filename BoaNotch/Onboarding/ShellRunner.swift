import Foundation

enum ShellRunner {
    struct Result {
        let output: String
        let exitCode: Int32
    }

    /// Run a shell command asynchronously. Never call from the main thread.
    static func run(_ command: String, environment: [String: String]? = nil) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]

                var env = ProcessInfo.processInfo.environment
                if let extra = environment {
                    for (k, v) in extra { env[k] = v }
                }
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: Result(output: output, exitCode: process.terminationStatus))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Check if a command exists on PATH
    static func commandExists(_ name: String) async -> Bool {
        let result = try? await run("which \(name)")
        return result?.exitCode == 0
    }
}
