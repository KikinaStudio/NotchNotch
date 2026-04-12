import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
    var thinkingContent: String
    var thinkingDuration: TimeInterval?
    var toolCallContent: String
    var subagentActivity: String
    let timestamp: Date
    var attachments: [Attachment]
    var isStreaming: Bool
    var promptTokens: Int? = nil
    var completionTokens: Int? = nil

    var totalTokens: Int? {
        guard let p = promptTokens, let c = completionTokens else { return nil }
        return p + c
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
        thinkingContent: String = "",
        toolCallContent: String = "",
        subagentActivity: String = "",
        timestamp: Date = Date(),
        attachments: [Attachment] = [],
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.toolCallContent = toolCallContent
        self.subagentActivity = subagentActivity
        self.timestamp = timestamp
        self.attachments = attachments
        self.isStreaming = isStreaming
    }
}
