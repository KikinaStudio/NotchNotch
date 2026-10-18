import Foundation

enum ShellRunner {
    struct Result {
        let output: String
        let exitCode: Int32
    }

    /// Run a shell command asynchronously. Never call from the main thread.
    static func run(_ command: String, environment: [String: String]? = nil) async throws -> Result {
        try await run(executable: "/bin/bash", arguments: ["-c", command], environment: environment)
    }

    /// Run an executable with arguments, no shell: paths need no quoting.
    /// stdout and stderr are merged. The pipe is drained before waiting:
    /// a child that writes more than the pipe buffer (64 KB, e.g. the Hermes
    /// installer's uv / pm output) would otherwise block forever.
    static func run(executable: String, arguments: [String], environment: [String: String]? = nil) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

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
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let output = String(decoding: data, as: UTF8.self)
                    continuation.resume(returning: Result(output: output, exitCode: process.terminationStatus))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Check if a command exists on PATH. An app opened from the Finder gets
    /// launchd's minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin): never use this
    /// for Hermes's own tools (`~/.local/bin`, `~/.hermes/tools`), and
    /// /usr/bin/git is a stub until the Command Line Tools are installed.
    static func commandExists(_ name: String) async -> Bool {
        let result = try? await run("which \(name)")
        return result?.exitCode == 0
    }
}
