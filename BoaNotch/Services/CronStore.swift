import Foundation
import os

struct CronJobRepeat: Codable {
    let times: Int?
    let completed: Int
}

struct CronJobSchedule: Codable {
    let kind: String
    let expr: String?
    let display: String?
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
    /// Consecutive failed runs: reset to 0 on success, +1 on an agent failure,
    /// untouched by a delivery failure (Hermes `cron/jobs.py` `_record_run_outcome`).
    /// Absent on older gateways and on records not run since.
    let failure_streak: Int?
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
        // `delivery_queued`: the run succeeded, its delivery is waiting in Hermes's queue.
        if let st = last_status, st != "ok", st != "delivery_queued" { return .failed }
        return .nominal
    }

    /// The run that just finished is the first failure of a series (`failure_streak == 1`).
    /// Without the field (older gateways), an ok → error transition seen across two loads.
    func isFirstFailure(previousStatus: String?) -> Bool {
        if let streak = failure_streak { return streak == 1 }
        return last_status == "error" && previousStatus == "ok"
    }

    /// First sentence of `last_error`, scrubbed, minus Python exception-class prefixes
    /// ("RuntimeError: "), like Hermes Desktop's `lastErrorSummary`. Hermes's own text
    /// (English): shown as-is, never parsed to guess what failed.
    var lastErrorSummary: String? {
        guard let raw = last_error?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        var text = HermesClient.scrubSecrets(raw)
        while let prefix = text.range(of: #"^[A-Za-z_][\w.]*(?:Error|Exception):\s*"#, options: .regularExpression) {
            text = String(text[prefix.upperBound...])
        }
        if let end = text.range(of: #"\.\s|\n"#, options: .regularExpression) {
            let keepsPeriod = text[end.lowerBound] == "."
            text = String(text[..<end.lowerBound]) + (keepsPeriod ? "." : "")
        }
        if text.count > 200 { text = String(text.prefix(199)) + "…" }
        return text.isEmpty ? nil : text
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

    /// Fires when a cron job completes with a non-[SILENT] response, whatever its
    /// `deliver` (Hermes saves a `.md` for every run).
    /// Wired by AppDelegate to present an in-notch toast. The `jobId` is
    /// propagated so downstream consumers (ChatMessage.routineId, the
    /// "Affine" button) can refer back to the originating CronJob without
    /// a fragile name-lookup.
    var onNewOutput: ((_ jobId: String, _ jobName: String, _ fullContent: String) -> Void)?

    /// Fires on the first failed run of a series (any `deliver`, [SILENT] included).
    /// Later failures of the same series stay quiet. Wired by AppDelegate to an error toast.
    var onFirstFailure: ((_ jobId: String, _ jobName: String) -> Void)?

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
            detectFinishedRuns(in: newJobs)
            jobs = newJobs
        } catch {
            print("[notchnotch] Failed to parse jobs.json: \(error)")
            jobs = []
        }
    }

    /// Diff `last_run_at` across loads to detect freshly-finished runs: an ok run surfaces
    /// its output, the first failure of a series an error toast. Hermes writes the `.md`
    /// before jobs.json, so the output is on disk when the diff fires.
    /// First load primes the map without firing callbacks (prevents toast storm on app launch,
    /// including for jobs already failing).
    private func detectFinishedRuns(in newJobs: [CronJob]) {
        let isFirstLoad = lastRunByJobId.isEmpty
        let previousStatus = Dictionary(
            jobs.compactMap { job in job.last_status.map { (job.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        for job in newJobs {
            guard let lastRun = job.last_run_at else { continue }
            let prev = lastRunByJobId[job.id]
            lastRunByJobId[job.id] = lastRun
            guard !isFirstLoad, prev != lastRun else { continue }
            if job.last_status == "ok" {
                guard let response = readLatestOutput(jobId: job.id) else { continue }
                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.uppercased().hasPrefix("[SILENT]") else { continue }
                onNewOutput?(job.id, job.name, trimmed)
            } else if let status = job.last_status, status != "delivery_queued" {
                let first = job.isFirstFailure(previousStatus: previousStatus[job.id])
                os_log("[notchnotch] mission %{public}@ run not ok (status %{public}@, streak %{public}@): %{public}@",
                       type: .info, job.id, status, job.failure_streak.map(String.init) ?? "nil",
                       first ? "toast" : "no toast")
                if first { onFirstFailure?(job.id, job.name) }
            }
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
