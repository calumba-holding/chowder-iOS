import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            Text(message.content)
                .font(.system(size: 17, weight: .regular, design: .default))
                .foregroundStyle(message.role == .user ? .white : .black)
                .padding(message.role == .user ? 12 : 0)
                .background(
                    message.role == .user
                        ? RoundedRectangle(cornerRadius: 18)
                            .fill(Color(red: 219/255, green: 84/255, blue: 75/255))
                        : nil
                )

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}
