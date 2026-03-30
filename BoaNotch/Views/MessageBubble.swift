import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                contentView
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if message.isStreaming && message.content.isEmpty {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 5, height: 5)
                        .offset(y: streamingOffset(for: i))
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                            value: message.isStreaming
                        )
                }
            }
            .frame(height: 20)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(markdownContent)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)

                if message.isStreaming && !message.content.isEmpty {
                    Text("▊")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var markdownContent: AttributedString {
        (try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.content)
    }

    private var bubbleBackground: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(.blue.opacity(0.6))
            : AnyShapeStyle(.white.opacity(0.1))
    }

    private func streamingOffset(for index: Int) -> CGFloat {
        message.isStreaming ? -3 : 0
    }
}
