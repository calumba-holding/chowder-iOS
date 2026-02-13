import ActivityKit
import SwiftUI
import WidgetKit

struct ChowderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChowderActivityAttributes.self) { context in
            // Lock Screen / StandBy banner
            lockScreenBanner(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded region (long-press on Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    PulsingDot(isFinished: context.state.isFinished)
                        .frame(width: 12, height: 12)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.agentName)
                            .font(.headline)
                        Text(context.state.currentStep)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.isFinished && !context.state.completedSteps.isEmpty {
                        Text("Step \(context.state.completedSteps.count + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.completedSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(context.state.completedSteps.suffix(4), id: \.self) { step in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.green)
                                    Text(step)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } compactLeading: {
                PulsingDot(isFinished: context.state.isFinished)
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                if context.state.isFinished {
                    Text("Done")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text(context.state.currentStep)
                        .font(.caption2)
                        .lineLimit(1)
                        .frame(maxWidth: 64)
                }
            } minimal: {
                PulsingDot(isFinished: context.state.isFinished)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Lock Screen Banner

    @ViewBuilder
    private func lockScreenBanner(context: ActivityViewContext<ChowderActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: pulsing dot + agent name + task
            HStack(spacing: 10) {
                PulsingDot(isFinished: context.state.isFinished)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.agentName)
                        .font(.system(size: 14, weight: .semibold))

                    Text(context.attributes.userTask)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if context.state.isFinished {
                    Text("Done")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            // Steps list: completed steps + current in-progress step
            VStack(alignment: .leading, spacing: 4) {
                ForEach(context.state.completedSteps.suffix(5), id: \.self) { step in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                        Text(step)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Current in-progress step (not finished)
                if !context.state.isFinished {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                        Text(context.state.currentStep)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Pulsing Dot

/// A small circle that gently scales up and down to indicate activity.
struct PulsingDot: View {
    var isFinished: Bool

    var body: some View {
        Circle()
            .fill(isFinished ? Color.green : Color.blue)
    }
}
