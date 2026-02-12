import SwiftUI

struct ChatHeaderView: View {
    let botName: String
    let isOnline: Bool
    var onSettingsTapped: (() -> Void)?
    var onDebugTapped: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Avatar + name tappable to open settings
                Button {
                    onSettingsTapped?()
                } label: {
                    HStack(spacing: 10) {
                        if let customAvatar = LocalStorage.loadAvatar() {
                            Image(uiImage: customAvatar)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        } else if let uiImage = UIImage(named: "BotAvatar") {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(red: 219/255, green: 84/255, blue: 75/255))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(String(botName.prefix(1)))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(botName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(isOnline ? "Online" : "Offline")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.gray)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onDebugTapped?()
                } label: {
                    Image(systemName: "ant")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 0.5)
        }
        .background {
            Color.white.opacity(0.75)
                .background(.thinMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }
}
