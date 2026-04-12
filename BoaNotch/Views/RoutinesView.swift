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
            Text("Routines")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(job.enabled ? .green.opacity(0.8) : .white.opacity(0.2))
                        .frame(width: 6, height: 6)

                    Text(job.schedule_display)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    if let lastRun = parseISO(job.last_run_at) {
                        Text(relativeTime(lastRun))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                Text(job.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func parseISO(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
