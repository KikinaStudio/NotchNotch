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
    let enabled: Bool
    let state: String?
    let next_run_at: String?
    let last_run_at: String?
    let last_status: String?
    let last_error: String?
    let deliver: String?
    let origin: CronJobOrigin?
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

    private func startWatching() {
        fd = open(jobsPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleFileChange()
        }
        source.resume()
        fileSource = source
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
