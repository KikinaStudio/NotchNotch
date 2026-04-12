import SwiftUI

struct RoutinesView: View {
    let cronStore: CronStore
    var onSelectJob: (CronJob) -> Void
    var onSelectTemplate: (String) -> Void
    var onCreateOwn: () -> Void
    var onDropFile: ([NSItemProvider]) -> Void

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
                    VStack(spacing: 4) {
                        ForEach(cronStore.sortedJobs) { job in
                            jobCard(job)
                        }

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showingBrowser = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 10))
                                Text("Browse templates")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(AppColors.accent.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 42)
        .padding(.bottom, 18)
    }

    private func jobCard(_ job: CronJob) -> some View {
        Button {
            onSelectJob(job)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                // Line 1: dot + name + schedule
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor(for: job))
                        .frame(width: 6, height: 6)
                        .opacity(job.state == "running" ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: job.state == "running")

                    Text(job.name.isEmpty ? String(job.prompt.prefix(40)) : job.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)

                    Spacer()

                    Text(job.schedule_display)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
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
                .padding(.leading, 12)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(job.state == "paused" ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
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
}
