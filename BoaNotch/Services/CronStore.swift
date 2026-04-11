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
    let next_run_at: String?
    let last_run_at: String?
    let last_status: String?
    let last_error: String?
    let deliver: String?
    let origin: CronJobOrigin?
}

class CronStore: ObservableObject {
    @Published var jobs: [CronJob] = []

    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var fd: Int32 = -1

    var sortedJobs: [CronJob] {
        jobs.sorted { a, b in
            if a.enabled != b.enabled { return a.enabled && !b.enabled }
            guard let aNext = a.next_run_at, let bNext = b.next_run_at else {
                return a.next_run_at != nil
            }
            return aNext < bNext
        }
    }

    private var jobsPath: String {
        let hermesHome = ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
        return "\(hermesHome)/cron/jobs.json"
    }

    init() {
        load()
        startWatching()
    }

    func load() {
        guard let data = FileManager.default.contents(atPath: jobsPath) else {
            jobs = []
            return
        }
        do {
            jobs = try JSONDecoder().decode([CronJob].self, from: data)
        } catch {
            print("[notchnotch] Failed to parse jobs.json: \(error)")
            jobs = []
        }
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
