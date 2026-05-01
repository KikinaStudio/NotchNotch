import Foundation

/// Single agent activity unit inside an assistant message: either a tool
/// invocation or a thinking block. Replaces the old aggregated string fields
/// (`thinkingContent`, `toolCallContent`, `subagentActivity`) with an
/// ordered, typed timeline that the bubble renders one line at a time.
///
/// `id` is the SSE `call_id` for tool events (so `started`/`completed`
/// payloads can be matched), or a fresh UUID for thinking events. `detail`
/// accumulates the raw substance for expanded view (tool args + result, or
/// thinking text) — capped at the SSE source (60 chars on tool result), so
/// what we store is what we got.
struct AgentEvent: Identifiable {
    let id: String
    let kind: Kind
    var status: Status
    let startedAt: Date
    var endedAt: Date?
    var detail: String

    enum Kind {
        case tool(name: String, argsPreview: String)
        case thinking
    }

    enum Status {
        case inProgress
        case completed
        case failed(String)
    }

    /// Snapshot duration. While in-progress, this reads `Date()` so the
    /// number is "live" — but the UI never renders it for in-progress
    /// events (the visible duration appears post-completion only). No
    /// `Timer.publish` / `TimelineView` needed.
    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var attachments: [Attachment]
    var isStreaming: Bool
    /// Ordered timeline of agent activity (tool calls + thinking blocks).
    /// Sole source of truth for the EventTimeline view in MessageBubble.
    var events: [AgentEvent] = []
    var promptTokens: Int? = nil
    var completionTokens: Int? = nil
    /// When the message is a cron-job delivery injected via the toast tap,
    /// this is the originating job's id. Drives the "Affine" button in
    /// MessageBubble. Live-only — not persisted in Hermes state.db, so
    /// reloads from session history come back as nil.
    var routineId: String? = nil

    var totalTokens: Int? {
        guard let p = promptTokens, let c = completionTokens else { return nil }
        return p + c
    }

    // MARK: - Event aggregations (computed, never stored)

    /// True when there's any agent activity to surface in the bubble.
    var hasEvents: Bool { !events.isEmpty }

    /// Sum of completed thinking blocks' durations. Ignores `.inProgress`
    /// (no end yet) and `.failed` (incomplete).
    var thinkingTotalDuration: TimeInterval {
        events.reduce(0) { acc, ev in
            guard case .thinking = ev.kind else { return acc }
            guard case .completed = ev.status else { return acc }
            return acc + ev.duration
        }
    }

    /// Number of tool calls that reached a terminal state. A `.failed` tool
    /// still counts in the recap ("Called 4 tools" can include 1 failed) —
    /// the failure surfaces visually when the timeline is expanded.
    var toolCallCount: Int {
        events.reduce(0) { acc, ev in
            guard case .tool = ev.kind else { return acc }
            switch ev.status {
            case .completed, .failed: return acc + 1
            case .inProgress:         return acc
            }
        }
    }

    /// The most recent in-progress event, or nil. Drives the single live
    /// header line during streaming. If multiple are in progress (rare),
    /// the last one wins.
    var currentEvent: AgentEvent? {
        events.reversed().first { event in
            if case .inProgress = event.status { return true }
            return false
        }
    }

    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        attachments: [Attachment] = [],
        isStreaming: Bool = false,
        routineId: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachments = attachments
        self.isStreaming = isStreaming
        self.routineId = routineId
    }
}
