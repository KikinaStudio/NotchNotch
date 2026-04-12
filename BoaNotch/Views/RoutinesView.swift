import SwiftUI
import UniformTypeIdentifiers

struct RoutinesView: View {
    let cronStore: CronStore
    var onSelectJob: (CronJob) -> Void
    var onSelectTemplate: (String) -> Void
    var onCreateOwn: () -> Void
    var onDropFile: ([NSItemProvider]) -> Void

    @State private var isDropTargeted = false
    @State private var isDashPulsing = false

    private let starterTemplates: [(icon: String, title: String, subtitle: String, draft: String)] = [
        (
            "bell.badge",
            "Remind me",
            "Set a reminder in 30 minutes, 1 hour, or tomorrow morning",
            "Remind me in 1 hour to check on the laundry."
        ),
        (
            "eye",
            "Watch for something",
            "Monitor the web for a keyword and alert you when it shows up",
            "Every 2 hours, search the web for 'iPhone 17 release date'. Only notify me if there is new concrete information. If nothing new, stay silent."
        ),
        (
            "newspaper",
            "Track a topic",
            "Follow a subject and get a daily summary of what happened",
            "Every morning at 9am, search for the latest news about artificial intelligence and send me a short summary of the 3 most important stories."
        ),
        (
            "figure.walk",
            "Daily habit",
            "A daily nudge to stay on track with a goal or habit",
            "Every day at 7am, give me a short and motivating workout routine I can do at home in 15 minutes. Vary the exercises each day."
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Tap one to get started, or describe your own in the chat.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 2)

            HStack(alignment: .top, spacing: 10) {
                // Left column: template cards
                VStack(spacing: 6) {
                    ForEach(Array(starterTemplates.enumerated()), id: \.offset) { _, template in
                        templateCard(template)
                    }
                }
                .frame(maxWidth: .infinity)

                // Right column: create your own zone
                createOwnZone
                    .frame(width: 140)
            }
        }
    }

    private var createOwnZone: some View {
        Button {
            onCreateOwn()
        } label: {
            VStack(spacing: 8) {
                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(AppColors.accent.opacity(0.5))

                Text("Create your own")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                Text("routine")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                Spacer().frame(height: 4)

                Group {
                    Text("or ") +
                    Text("drag here").foregroundColor(AppColors.accent.opacity(0.6)) +
                    Text(" a file to")
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))

                Text("start a routine")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))

                Spacer()
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .foregroundStyle(AppColors.accent.opacity(isDropTargeted ? (isDashPulsing ? 0.5 : 0.2) : 0))
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isDashPulsing)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            onDropFile(providers)
            return true
        }
        .onChange(of: isDropTargeted) { _, targeted in
            isDashPulsing = targeted
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
                        .lineLimit(3)
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
