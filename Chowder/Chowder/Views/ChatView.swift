import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var isAtBottom = true
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    // Spacer to push content below header
                    Color.clear.frame(height: 72)

                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        // Thinking shimmer — shown while the agent is working
                        if let activity = viewModel.currentActivity,
                           !activity.currentLabel.isEmpty {
                            ThinkingShimmerView(label: activity.currentLabel) {
                                viewModel.showActivityCard = true
                            }
                            .id("shimmer")
                            .transition(.opacity)
                        }

                        // Invisible anchor — must be inside LazyVStack so
                        // onAppear/onDisappear track scroll visibility.
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                            .onAppear { withAnimation(.easeOut(duration: 0.12)) { isAtBottom = true } }
                            .onDisappear { withAnimation(.easeOut(duration: 0.12)) { isAtBottom = false } }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .overlay(alignment: .bottom) {
                    if !isAtBottom {
                        Button {
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(.secondaryLabel))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(.systemBackground))
                                )
                                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                        }
                        .padding(.bottom, 10)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .onChange(of: viewModel.messages.count) {
                    // New message added (user sent or assistant placeholder) — always scroll to bottom
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.last?.content) {
                    // Streaming delta — only auto-scroll if already at bottom
                    guard isAtBottom else { return }
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.currentActivity?.currentLabel) {
                    // Shimmer appeared/updated — only auto-scroll if already at bottom
                    guard isAtBottom else { return }
                    if viewModel.currentActivity != nil {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }

            // Input bar
            HStack(spacing: 12) {
                TextField("Message...", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading
                                ? Color(.systemGray4)
                                : Color.blue
                        )
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .overlay(alignment: .top) {
            ChatHeaderView(
                botName: viewModel.botName,
                isOnline: viewModel.isConnected,
                onSettingsTapped: { viewModel.showSettings = true },
                onDebugTapped: { viewModel.showDebugLog = true }
            )
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.connect()
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                currentIdentity: viewModel.botIdentity,
                currentProfile: viewModel.userProfile,
                isConnected: viewModel.isConnected,
                onSave: { identity, profile in
                    viewModel.saveWorkspaceData(identity: identity, profile: profile)
                },
                onSaveConnection: {
                    viewModel.reconnect()
                },
                onClearHistory: { viewModel.clearMessages() }
            )
        }
        .sheet(isPresented: $viewModel.showActivityCard) {
            if let activity = viewModel.currentActivity ?? viewModel.lastCompletedActivity {
                AgentActivityCard(activity: activity)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $viewModel.showDebugLog) {
            NavigationStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.debugLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(12)
                }
                .onAppear { viewModel.flushLogBuffer() }
                .navigationTitle("Debug Log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { viewModel.showDebugLog = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        HStack(spacing: 12) {
                            Button("Clear") { viewModel.debugLog.removeAll() }
                            Button("Copy") {
                                UIPasteboard.general.string = viewModel.debugLog.joined(separator: "\n")
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ChatView()
}
