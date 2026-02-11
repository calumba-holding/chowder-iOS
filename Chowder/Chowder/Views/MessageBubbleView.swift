import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            Group {
                if message.role == .assistant {
                    MarkdownContentView(message.content, foregroundColor: Color(.label))
                        .font(.system(size: 17))
                        .textSelection(.enabled)
                } else {
                    Text(message.content)
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .foregroundStyle(.white)
                }
            }
            .padding(message.role == .user ? 12 : 0)
            .background(
                message.role == .user
                    ? RoundedRectangle(cornerRadius: 18)
                        .fill(Color.blue)
                    : nil
            )

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}
