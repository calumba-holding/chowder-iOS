import ActivityKit
import SwiftUI
import WidgetKit

struct ChowderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChowderActivityAttributes.self) { context in
            lockScreenBanner(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Circle()
                        .fill(context.state.isFinished ? Color.green : Color.blue)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.userTask)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        if !context.state.isFinished {
                            Text(context.state.currentIntent)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Step \(context.state.stepNumber)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let prev = context.state.previousIntent, !context.state.isFinished {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.yellow)
                            Text(prev)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Circle()
                    .fill(context.state.isFinished ? Color.green : Color.blue)
                    .frame(width: 6, height: 6)
            } compactTrailing: {
                if context.state.isFinished {
                    Text("Done")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text(context.state.currentIntent)
                        .font(.caption2)
                        .lineLimit(1)
                        .frame(maxWidth: 64)
                }
            } minimal: {
                Circle()
                    .fill(context.state.isFinished ? Color.green : Color.blue)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Lock Screen Banner

    @ViewBuilder
    private func lockScreenBanner(context: ActivityViewContext<ChowderActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Row 1: Header (OpenClaw > task + intent/timer) + Cost ──
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    // "OpenClaw > user task"
                    HStack(spacing: 4) {
                        Text("OpenClaw")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Image(systemName: "arrow.forward")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(context.state.subject ?? context.attributes.userTask)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    // Current intent ALL CAPS + timer (or "DONE" when finished)
                    if context.state.isFinished {
                        Text("DONE")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 247/255, green: 90/255, blue: 77/255))

                            Text(context.state.currentIntent)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .textCase(.uppercase)
                                .lineLimit(1)
                                .contentTransition(.numericText())

                            Text(
                                timerInterval: context.state.intentStartDate...Date.now.addingTimeInterval(3600),
                                countsDown: false
                            )
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 56, alignment: .leading)
                        }
                    }
                }

                Spacer()

                if let cost = context.state.costTotal {
                    Text(cost)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color(red: 255/255, green: 80/255, blue: 65/255))
                        )
                }
            }

            Spacer()

            // ── Row 2: Previous intent (large, wraps to 2 lines) ──
            Group {
                if let prev = context.state.previousIntent, !context.state.isFinished {
                    Text(prev + "...")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .lineSpacing(-4)
                        .lineLimit(2)
                        .mask(ShimmerMask())
                        .transition(.push(from: .bottom))
                } else if context.state.isFinished {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 28, height: 28)
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .transition(.scale.combined(with: .opacity))
                        Text("Task Complete")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(minHeight: 58, alignment: .bottomLeading)
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .activityBackgroundTint(.black)
    }
}

// MARK: - Shimmer Mask

/// A gradient mask that gives a soft shimmer effect on the active intent text.
struct ShimmerMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.4), location: 0),
                .init(color: .white, location: 0.3),
                .init(color: .white, location: 0.7),
                .init(color: .white.opacity(0.4), location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
