import Foundation

struct CronJobRepeat: Codable {
    let times: Int?
    let completed: Int
}

struct CronJobSchedule: Codable {
    let kind: String
}

struct CronJobOrigin: Codable {
    let platform: String?
    let chat_id: String?
    let chat_name: String?
}

struct CronJob: Identifiable, Codable {
    let id: String
    let name: String
    let prompt: String
    let schedule: CronJobSchedule
    let schedule_display: String
    let `repeat`: CronJobRepeat?
    var enabled: Bool
    var state: String?
    let next_run_at: String?
    let last_run_at: String?
    let last_status: String?
    let last_error: String?
    let deliver: String?
    let origin: CronJobOrigin?
}

// MARK: - Routine classification

/// Type of routine derived from prompt + delivery + schedule cadence.
/// `silent`: in-process work (prompt prefixed `[SILENT]`) or remote-delivered jobs.
/// `digest`: local-delivered, daily-or-rarer cadence (informational summary).
/// `alert`: local-delivered, sub-daily cadence (rapid-fire monitoring).
enum RoutineType { case silent, digest, alert }

/// Surfaceable status for a routine card.
/// `nominal` and `paused` carry no pill (paused = toggle off + opacity 50%).
/// `failed` shows a small chip when the most recent run reported a non-ok status.
enum RoutineStatus { case nominal, failed, paused }

extension CronJob {
    var routineType: RoutineType {
        if prompt.uppercased().hasPrefix("[SILENT]") { return .silent }
        // Delivery channel is orthogonal to routine type: a daily Telegram
        // briefing is still a digest; a high-frequency Slack monitor is still
        // an alert. Only the [SILENT] marker truly means "background, no one
        // gets pinged".
        let s = schedule_display.lowercased()
        if s.hasPrefix("every ") {
            if let h = Self.parseEveryHours(s), h < 24 { return .alert }
            if let m = Self.parseEveryMinutes(s), m < 1440 { return .alert }
            return .digest
        }
        let parts = s.split(separator: " ").map(String.init)
        if parts.count == 5 {
            // Step values in minute or hour field => sub-daily cadence.
            if parts[0].contains("/") || parts[1].contains("/") { return .alert }
            return .digest
        }
        return .digest
    }

    var routineStatus: RoutineStatus {
        if !enabled || state == "paused" { return .paused }
        if let st = last_status, st != "ok" { return .failed }
        return .nominal
    }

    /// "every 2h" / "every 24h" -> 2 / 24. Ignores minute-only forms.
    private static func parseEveryHours(_ s: String) -> Int? {
        let trimmed = s.replacingOccurrences(of: "every ", with: "")
            .trimmingCharacters(in: .whitespaces)
        // "2h", "24h" — must end with h and contain no m
        guard trimmed.hasSuffix("h"), !trimmed.contains("m") else { return nil }
        return Int(trimmed.dropLast())
    }

    /// "every 30m" / "every 90m" -> 30 / 90. Ignores hour-only forms.
    private static func parseEveryMinutes(_ s: String) -> Int? {
        let trimmed = s.replacingOccurrences(of: "every ", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("m"), !trimmed.contains("h") else { return nil }
        return Int(trimmed.dropLast())
    }
}

class CronStore: ObservableObject {
    @Published var jobs: [CronJob] = []

    /// Fires when a cron job completes (deliver=local) with a non-[SILENT] response.
    /// Wired by AppDelegate to present an in-notch toast.
    var onNewOutput: ((_ jobName: String, _ fullContent: String) -> Void)?

    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var fd: Int32 = -1
    private var lastRunByJobId: [String: String] = [:]

    var sortedJobs: [CronJob] {
        jobs.sorted { a, b in
            if a.enabled != b.enabled { return a.enabled && !b.enabled }
            guard let aNext = a.next_run_at, let bNext = b.next_run_at else {
                return a.next_run_at != nil
            }
            return aNext < bNext
        }
    }

    private var hermesHome: String {
        ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
    }

    private var jobsPath: String { "\(hermesHome)/cron/jobs.json" }
    private var outputRoot: String { "\(hermesHome)/cron/output" }

    init() {
        load()
        startWatching()
    }

    private struct JobsWrapper: Codable {
        let jobs: [CronJob]
    }

    func load() {
        guard let data = FileManager.default.contents(atPath: jobsPath) else {
            jobs = []
            return
        }
        do {
            // jobs.json can be {"jobs": [...]} or bare [...]
            let newJobs: [CronJob]
            if let wrapper = try? JSONDecoder().decode(JobsWrapper.self, from: data) {
                newJobs = wrapper.jobs
            } else {
                newJobs = try JSONDecoder().decode([CronJob].self, from: data)
            }
            detectNewOutputs(in: newJobs)
            jobs = newJobs
        } catch {
            print("[notchnotch] Failed to parse jobs.json: \(error)")
            jobs = []
        }
    }

    /// Diff `last_run_at` across loads to detect freshly-completed jobs with local delivery.
    /// First load primes the map without firing callbacks (prevents toast storm on app launch).
    private func detectNewOutputs(in newJobs: [CronJob]) {
        let isFirstLoad = lastRunByJobId.isEmpty
        for job in newJobs {
            guard let lastRun = job.last_run_at else { continue }
            let prev = lastRunByJobId[job.id]
            lastRunByJobId[job.id] = lastRun
            guard !isFirstLoad, prev != lastRun, job.last_status == "ok" else { continue }
            guard let response = readLatestOutput(jobId: job.id) else { continue }
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.uppercased().hasPrefix("[SILENT]") else { continue }
            onNewOutput?(job.name, trimmed)
        }
    }

    private func readLatestOutput(jobId: String) -> String? {
        let dir = "\(outputRoot)/\(jobId)"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        let mdFiles = files.filter { $0.hasSuffix(".md") }
        guard let latest = mdFiles.max() else { return nil }
        let path = "\(dir)/\(latest)"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        if let range = content.range(of: "## Response") {
            let after = content[range.upperBound...]
            return String(after)
        }
        return nil
    }

    /// Optimistically flip a job's pause state in the local copy so the UI
    /// updates instantly while the REST round-trip is in flight. Reconciled
    /// when the file watcher reloads jobs.json after Hermes rewrites it.
    /// Caller is responsible for reverting on REST failure.
    func applyOptimisticPause(jobId: String, paused: Bool) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        var job = jobs[idx]
        job.enabled = !paused
        job.state = paused ? "paused" : "scheduled"
        jobs[idx] = job
    }

    private func startWatching() {
        fd = open(jobsPath, O_EVTONLY)
        guard fd >= 0 else { return }

        // .delete / .rename fire when Hermes does an atomic write
        // (write to tmp + rename over the original). On those events we
        // close the orphan FD and reattach to the new inode, otherwise
        // the watcher goes silent after the first rewrite.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.reattachWatcher()
            }
            self.handleFileChange()
        }
        source.resume()
        fileSource = source
    }

    private func reattachWatcher() {
        fileSource?.cancel()
        fileSource = nil
        if fd >= 0 { close(fd); fd = -1 }
        // The file may not exist for a brief window between unlink and rename;
        // retry briefly so we don't drop the watch on a slow filesystem.
        Task { @MainActor in
            for _ in 0..<10 {
                if FileManager.default.fileExists(atPath: jobsPath) {
                    self.startWatching()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            self.startWatching() // last attempt — startWatching is no-op on failure
        }
    }

    private func handleFileChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.load()
        }
    }

    deinit {
        fileSource?.cancel()
        if fd >= 0 { close(fd) }
    }
}
