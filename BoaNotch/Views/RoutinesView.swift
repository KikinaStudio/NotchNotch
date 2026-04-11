import SwiftUI

struct RoutinesView: View {
    let cronStore: CronStore
    var onSelectJob: (CronJob) -> Void
    var onSelectTemplate: (String) -> Void

    private let starterTemplates: [(icon: String, title: String, subtitle: String, draft: String)] = [
        (
            "bell.badge",
            "Remind me",
            "Set a reminder in 30 minutes, 1 hour, or tomorrow morning",
            "Remind me in 1 hour to check on the laundry."
        ),
        (
            "sun.max",
            "Morning digest",
            "Every morning, get a summary of the news on a topic you care about",
            "Every morning at 9am, search for the latest news about technology and give me a short summary with the 5 most important stories."
        ),
        (
            "clock.badge.checkmark",
            "Daily reminder",
            "A recurring nudge at the time you pick — take a break, drink water, anything",
            "Every day at 2pm, remind me to take a 10-minute break and stretch."
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routines")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            if cronStore.sortedJobs.isEmpty {
                starterTemplatesView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(cronStore.sortedJobs) { job in
                            jobCard(job)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 30)
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

    private var starterTemplatesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tap one to get started, or describe your own in the chat.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))

            ForEach(Array(starterTemplates.enumerated()), id: \.offset) { _, template in
                templateCard(template)
            }
        }
    }

    private func templateCard(_ template: (icon: String, title: String, subtitle: String, draft: String)) -> some View {
        Button {
            onSelectTemplate(template.draft)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: template.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.accent.opacity(0.6))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Text(template.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            )
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
