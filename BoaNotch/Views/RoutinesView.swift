import SwiftUI

struct RoutinesView: View {
    let cronStore: CronStore
    let panelSize: PanelSize
    var onSelectJob: (CronJob) -> Void
    var onSelectTemplate: (String) -> Void
    var onCreateOwn: () -> Void
    var onDropFile: ([NSItemProvider]) -> Void
    var onDraftAction: ((String, Bool) -> Void)? = nil
    var onCreateCustomRoutine: ((String) -> Void)? = nil
    var onSetPaused: ((CronJob, Bool) -> Void)? = nil

    @State private var showingBrowser = false
    @State private var showingCustomForm = false
    @State private var hoveredJobId: String?
    @State private var hoveredAddCard = false

    @State private var formName: String = ""
    @State private var formPrompt: String = ""
    @State private var formDeliver: String = "Notch"

    @State private var scheduleFrequency: ScheduleFrequency = .daily
    @State private var scheduleTime: Date = Self.defaultScheduleTime()
    @State private var selectedWeekdays: Set<Int> = [1]
    @State private var dayOfMonth: Int = 1
    @State private var intervalHours: Int = 2

    private enum ScheduleFrequency: String, CaseIterable, Hashable {
        case daily = "Daily"
        case weekdays = "Weekdays"
        case weekly = "Weekly"
        case monthly = "Monthly"
        case hourly = "Hourly"
    }

    private let deliverOptions: [(name: String, icon: String)] = [
        ("Notch", "bell.badge.fill"),
        ("Telegram", "paperplane.fill"),
        ("Discord", "bubble.left.fill"),
        ("Slack", "number")
    ]
    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let hourIntervals: [Int] = [1, 2, 3, 4, 6, 12]

    private static func defaultScheduleTime() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private var gridColumns: [GridItem] {
        // .large panel (900pt wide) → 3 columns, .standard (680pt) → 2 columns
        let count = panelSize == .large ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showingCustomForm {
                customForm
                    .transition(.opacity)
            } else if cronStore.sortedJobs.isEmpty || showingBrowser {
                TemplateBrowserView(
                    panelSize: panelSize,
                    onSelectTemplate: onSelectTemplate,
                    onCreateOwn: onCreateOwn
                )
            } else {
                FadingScrollView {
                    VStack(spacing: 14) {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                            ForEach(cronStore.sortedJobs) { job in
                                jobCard(job)
                            }
                            addCard
                        }

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showingBrowser = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                Text("Browse templates")
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppColors.accent.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(AppColors.accent.opacity(0.3), lineWidth: 0.5)
                            )
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
        let hasName = !job.name.isEmpty
        let title = hasName ? job.name : String(job.prompt.prefix(40))
        let isPaused = job.state == "paused"
        let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        let isActive = job.enabled && job.state != "paused"
        let hasError = (job.last_status != nil) && (job.last_status != "ok")
        let dotState: StatusDotButton.DotState = {
            if !isActive { return .off }
            if hasError { return .error }
            return .on
        }()

        let routineType = job.routineType

        return Button {
            onSelectJob(job)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: type glyph (silent / digest / alert) + title
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: Self.iconName(for: routineType))
                        .font(DS.Icon.routineType)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColors.accent)
                        .accessibilityLabel(Self.accessibilityLabel(for: routineType))

                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }

                // Row 2: description (only when title is distinct from prompt)
                if hasName {
                    Text(job.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Row 3: failure pill + contextual info line + on/off dot
                HStack(spacing: 8) {
                    StatusPill(status: job.routineStatus)

                    Text(footerText(for: job))
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Surface.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StatusDotButton(state: dotState) {
                        onSetPaused?(job, isActive)
                    }
                    .accessibilityLabel(isActive ? "Pause \(title)" : "Resume \(title)")
                }
                .padding(.top, 5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape.fill(.quaternary.opacity(0.6)))
            .overlay(
                cardShape
                    .fill(hoveredJobId == job.id ? AnyShapeStyle(DS.Stroke.hairline) : AnyShapeStyle(Color.clear))
                    .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .opacity(isPaused ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: hoveredJobId == job.id)
        }
        .buttonStyle(.plain)
        .help(tooltipText(for: job))
        .onHover { over in hoveredJobId = over ? job.id : nil }
        .pointingHandCursor()
        .contextMenu {
            Button {
                let name = job.name.isEmpty ? String(job.prompt.prefix(30)) : job.name
                onDraftAction?("Change the schedule of \"\(name)\" to ", false)
            } label: {
                Label("Change schedule", systemImage: "clock")
            }

            Button {
                let isCurrentlyActive = job.enabled && job.state != "paused"
                onSetPaused?(job, isCurrentlyActive)
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

    // MARK: - Routine type styling

    private static func iconName(for type: RoutineType) -> String {
        switch type {
        case .silent: return "eye.fill"
        case .digest: return "calendar"
        case .alert:  return "bell.fill"
        }
    }

    private static func accessibilityLabel(for type: RoutineType) -> String {
        switch type {
        case .silent: return "Silent routine"
        case .digest: return "Digest routine"
        case .alert:  return "Alert routine — notifies in the notch"
        }
    }

    // MARK: - Footer text

    private func footerText(for job: CronJob) -> String {
        humanSchedule(job.schedule_display)
    }

    /// Multi-line content for the native `.help()` tooltip on the pill.
    /// Phrasing varies by routine type (runs/deliveries/checks) but the
    /// data shape is identical: count + last_run + next_run + optional error.
    private func tooltipText(for job: CronJob) -> String {
        let runs = job.repeat?.completed ?? 0
        let lastRel = relativeTime(job.last_run_at)
        let nextRel = relativeTime(job.next_run_at)

        let (countNoun, lastLabel, nextLabel): (String, String, String) = {
            switch job.routineType {
            case .silent: return ("runs", "Last run", "Next run")
            case .digest: return ("deliveries", "Last", "Next")
            case .alert:  return ("checks", "Last check", "Next check")
            }
        }()

        var lines: [String] = []
        if runs > 0 { lines.append("\(runs) \(countNoun)") }
        if let lastRel { lines.append("\(lastLabel): \(lastRel)") }
        if let nextRel { lines.append("\(nextLabel): \(nextRel)") }

        if job.routineStatus == .failed, let err = job.last_error, !err.isEmpty {
            lines.insert("Error: \(err)", at: 0)
        }

        return lines.isEmpty ? "No data yet" : lines.joined(separator: "\n")
    }

    private func relativeTime(_ iso: String?) -> String? {
        guard let date = parseISO(iso) else { return nil }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    private func parseISO(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
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

    // MARK: - Add card (last grid cell)

    private var addCard: some View {
        let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            resetForm()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showingCustomForm = true
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(DS.Icon.large.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                Text("Create routine")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.accent.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: addCardHeight, alignment: .center)
            .background(cardShape.fill(.quaternary.opacity(0.35)))
            .overlay(
                cardShape.strokeBorder(
                    AppColors.accent.opacity(hoveredAddCard ? 0.75 : 0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            )
            .overlay(
                cardShape
                    .fill(hoveredAddCard ? AppColors.accent.opacity(0.06) : .clear)
                    .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredAddCard = $0 }
        .pointingHandCursor()
        .animation(.easeInOut(duration: 0.15), value: hoveredAddCard)
    }

    // Matches the approximate height of a populated jobCard so the grid stays aligned.
    private var addCardHeight: CGFloat { 96 }

    // MARK: - Custom form

    private var customForm: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Back button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showingCustomForm = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption2.weight(.bold))
                        Text("New routine")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                formField(label: "Name", optional: true) {
                    TextField("e.g. Morning briefing", text: $formName)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
                }

                formField(label: "What should it do?", optional: false) {
                    TextEditor(text: $formPrompt)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .frame(minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
                }

                formField(label: "When?", optional: false) {
                    scheduleSection
                }

                formField(label: "Deliver to", optional: false) {
                    HStack(spacing: 6) {
                        ForEach(deliverOptions, id: \.name) { option in
                            let isSelected = formDeliver == option.name
                            Button {
                                formDeliver = option.name
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: option.icon)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(isSelected ? AnyShapeStyle(.black.opacity(0.75)) : AnyShapeStyle(.secondary))
                                    Text(option.name)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(isSelected ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(.secondary))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppColors.accent)
                                    } else {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                    }
                }

                Button {
                    submitCustomRoutine()
                } label: {
                    Text("Create routine")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(customFormValid ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if customFormValid {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppColors.accent.opacity(0.35))
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6))
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(!customFormValid)
                .pointingHandCursor()
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Schedule picker

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                    frequencyPill(freq)
                }
                if scheduleFrequency != .hourly {
                    timeRow.padding(.leading, 6)
                }
            }

            scheduleExtras

            Text(humanSchedule(composedCron))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var scheduleExtras: some View {
        switch scheduleFrequency {
        case .daily, .weekdays:
            EmptyView()
        case .weekly:
            weekdayPicker
        case .monthly:
            dayOfMonthControl
        case .hourly:
            intervalPicker
        }
    }

    private func frequencyPill(_ freq: ScheduleFrequency) -> some View {
        let isSelected = scheduleFrequency == freq
        return Button {
            scheduleFrequency = freq
        } label: {
            Text(freq.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppColors.accent)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6))
                    }
                }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { idx in
                let isSelected = selectedWeekdays.contains(idx)
                Button {
                    if isSelected {
                        if selectedWeekdays.count > 1 {
                            selectedWeekdays.remove(idx)
                        }
                    } else {
                        selectedWeekdays.insert(idx)
                    }
                } label: {
                    Text(weekdayLabels[idx])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(.secondary))
                        .frame(width: 26, height: 26)
                        .background {
                            if isSelected {
                                Circle().fill(AppColors.accent)
                            } else {
                                Circle().fill(.quaternary.opacity(0.6))
                            }
                        }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    private var timeRow: some View {
        HStack(spacing: 8) {
            Text("at")
                .font(.caption)
                .foregroundStyle(.tertiary)
            DatePicker("", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
                .frame(minWidth: 84)
        }
    }

    private var dayOfMonthControl: some View {
        HStack(spacing: 6) {
            Text("Day")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Stepper(value: $dayOfMonth, in: 1...28) {
                Text("\(dayOfMonth)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 20, alignment: .trailing)
            }
            .labelsHidden()
        }
    }

    private var intervalPicker: some View {
        HStack(spacing: 6) {
            Text("Every")
                .font(.caption)
                .foregroundStyle(.tertiary)
            ForEach(hourIntervals, id: \.self) { h in
                let isSelected = intervalHours == h
                Button {
                    intervalHours = h
                } label: {
                    Text("\(h)h")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppColors.accent)
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6))
                            }
                        }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    private var composedCron: String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: scheduleTime)
        let m = cal.component(.minute, from: scheduleTime)
        switch scheduleFrequency {
        case .daily:
            return "\(m) \(h) * * *"
        case .weekdays:
            return "\(m) \(h) * * 1-5"
        case .weekly:
            let days = selectedWeekdays.sorted().map(String.init).joined(separator: ",")
            return "\(m) \(h) * * \(days.isEmpty ? "1" : days)"
        case .monthly:
            return "\(m) \(h) \(dayOfMonth) * *"
        case .hourly:
            return "0 */\(intervalHours) * * *"
        }
    }

    private func formField<Content: View>(
        label: String,
        optional: Bool,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if optional {
                    Text("(optional)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            content()
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var customFormValid: Bool {
        !formPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resetForm() {
        formName = ""
        formPrompt = ""
        formDeliver = "Notch"
        scheduleFrequency = .daily
        scheduleTime = Self.defaultScheduleTime()
        selectedWeekdays = [1]
        dayOfMonth = 1
        intervalHours = 2
    }

    private func submitCustomRoutine() {
        guard customFormValid else { return }
        let name = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = formPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let deliverKey = formDeliver == "Notch" ? "local" : formDeliver.lowercased()

        var headerParts: [String] = ["Create a new routine"]
        if !name.isEmpty { headerParts.append("named \"\(name)\"") }
        headerParts.append("running on cron schedule \(composedCron)")
        headerParts.append("delivered via \(deliverKey)")
        let draft = headerParts.joined(separator: " ") + ".\n\nThe routine should: \(prompt)"

        onCreateCustomRoutine?(draft)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showingCustomForm = false
        }
    }
}

// MARK: - StatusPill

/// Compact failure chip shown bottom-leading on a routine card when its
/// last run reported a non-ok status. Renders nothing for `.nominal` /
/// `.paused` (paused is already conveyed by the toggle dot + 50% card opacity).
struct StatusPill: View {
    let status: RoutineStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
            Text(label)
                .font(DS.Text.microMedium)
                .foregroundStyle(DS.Surface.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(DS.Surface.quaternary))
    }

    private var label: String {
        switch status {
        case .nominal: return "active"
        case .failed:  return "failed"
        case .paused:  return "paused"
        }
    }
}

