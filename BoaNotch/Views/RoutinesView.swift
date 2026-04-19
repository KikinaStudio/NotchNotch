import SwiftUI

struct RoutinesView: View {
    let cronStore: CronStore
    var onSelectJob: (CronJob) -> Void
    var onSelectTemplate: (String) -> Void
    var onCreateOwn: () -> Void
    var onDropFile: ([NSItemProvider]) -> Void
    var onDraftAction: ((String, Bool) -> Void)? = nil

    @State private var showingBrowser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text("Routines")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                if !cronStore.jobs.isEmpty {
                    Text("(\(cronStore.jobs.count))")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }

            if cronStore.sortedJobs.isEmpty || showingBrowser {
                TemplateBrowserView(
                    onSelectTemplate: onSelectTemplate,
                    onCreateOwn: onCreateOwn
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(cronStore.sortedJobs.enumerated()), id: \.element.id) { index, job in
                            if index > 0 { rowDivider }
                            jobCard(job)
                        }

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showingBrowser = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 11))
                                Text("Browse templates")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(AppColors.accent.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(AppColors.accent.opacity(0.25), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .padding(.top, 14)
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 42)
        .padding(.bottom, 18)
    }

    @State private var hoveredJobId: String?

    private var rowDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 13)
    }

    private func jobCard(_ job: CronJob) -> some View {
        Button {
            onSelectJob(job)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                // Line 1: dot + name + schedule pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor(for: job))
                        .frame(width: 7, height: 7)
                        .opacity(job.state == "running" ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: job.state == "running")

                    Text(job.name.isEmpty ? String(job.prompt.prefix(40)) : job.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)

                    Spacer()

                    Text(humanSchedule(job.schedule_display))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .tracking(0.3)
                        .lineLimit(1)
                }

                // Line 2: telemetry
                HStack(spacing: 0) {
                    let runCount = job.repeat?.completed ?? 0
                    let nextRun = formatNextRun(job.next_run_at)
                    let hasRuns = runCount > 0
                    let hasNext = job.state == "scheduled" && nextRun != nil

                    if hasRuns || hasNext {
                        if hasRuns {
                            Text("\(runCount) runs")
                        }
                        if hasRuns && hasNext {
                            Text(" · ")
                        }
                        if hasNext {
                            Text("next: \(nextRun!)")
                        }
                    } else {
                        Text("not yet run")
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.25))
                .padding(.leading, 13)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(hoveredJobId == job.id ? 0.05 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .opacity(job.state == "paused" ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: hoveredJobId == job.id)
        }
        .buttonStyle(.plain)
        .onHover { over in hoveredJobId = over ? job.id : nil }
        .contextMenu {
            Button {
                let name = job.name.isEmpty ? String(job.prompt.prefix(30)) : job.name
                onDraftAction?("Change the schedule of \"\(name)\" to ", false)
            } label: {
                Label("Change schedule", systemImage: "clock")
            }

            Button {
                let name = job.name.isEmpty ? String(job.prompt.prefix(30)) : job.name
                let verb = job.state == "paused" ? "Resume" : "Pause"
                onDraftAction?("\(verb) the routine \"\(name)\"", true)
            } label: {
                Label(
                    job.state == "paused" ? "Resume" : "Pause",
                    systemImage: job.state == "paused" ? "play" : "pause"
                )
            }

            Button(role: .destructive) {
                let name = job.name.isEmpty ? String(job.prompt.prefix(30)) : job.name
                onDraftAction?("Remove the routine \"\(name)\"", false)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func dotColor(for job: CronJob) -> Color {
        switch job.state {
        case "running": return AppColors.accent
        case "paused": return .orange
        default: return job.enabled ? .green.opacity(0.8) : .white.opacity(0.2)
        }
    }

    private func parseISO(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }

    private func formatNextRun(_ string: String?) -> String? {
        guard let date = parseISO(string) else { return nil }
        let fmt = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            fmt.dateFormat = "h:mm a"
        } else {
            fmt.dateFormat = "MMM d"
        }
        return fmt.string(from: date)
    }

    private func humanSchedule(_ raw: String) -> String {
        // Handle "every Xm/Xh" style
        if raw.hasPrefix("every ") { return raw }

        // Parse 5-field cron: min hour dom month dow
        let parts = raw.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return raw }
        let (min, hour, dom, _, dow) = (parts[0], parts[1], parts[2], parts[3], parts[4])

        // Format time from hour+min fields
        func timeStr(_ h: String, _ m: String) -> String? {
            guard let hi = Int(h), let mi = Int(m), hi < 24, mi < 60 else { return nil }
            let ampm = hi >= 12 ? "PM" : "AM"
            let h12 = hi == 0 ? 12 : (hi > 12 ? hi - 12 : hi)
            return mi == 0 ? "\(h12) \(ampm)" : "\(h12):\(String(format: "%02d", mi)) \(ampm)"
        }

        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        func dowLabel(_ d: String) -> String {
            // "1-5" -> "Weekdays", "0" -> "Sun", "1,4" -> "Mon & Thu"
            if d == "*" { return "Daily" }
            if d == "1-5" { return "Weekdays" }
            if d == "0,6" || d == "6,0" { return "Weekends" }
            let indices = d.split(separator: ",").compactMap { Int($0) }
            if !indices.isEmpty {
                let names = indices.compactMap { $0 < 7 ? dayNames[$0] : nil }
                if names.count == 1 { return names[0] + "s" }
                return names.joined(separator: " & ")
            }
            return d
        }

        // "*/N * * * *" -> every N minutes
        if min.hasPrefix("*/"), hour == "*" {
            let n = String(min.dropFirst(2))
            return "Every \(n) min"
        }

        // "0 */N * * *" -> every N hours
        if hour.hasPrefix("*/") {
            let n = String(hour.dropFirst(2))
            return "Every \(n)h"
        }

        // Fixed hour+min
        if let time = timeStr(hour, min) {
            if dom != "*" {
                return "Day \(dom), \(time)"
            }
            let days = dowLabel(dow)
            if days == "Daily" { return "Daily at \(time)" }
            return "\(days) at \(time)"
        }

        return raw
    }
}
