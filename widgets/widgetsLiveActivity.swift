import WidgetKit
import SwiftUI
import AlarmKit

/// Live Activity widget for AlarmKit alarms.
/// Shows alarm info in Dynamic Island and on Lock Screen.
/// AlarmKit manages the lifecycle — this just provides the UI.
struct ShabbatClockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ShabbatAlarmMetadata>.self) { context in
            // Lock Screen / StandBy presentation
            lockScreenView(context: context)
        } dynamicIsland: { context in
            let metadata = context.attributes.metadata
            let isShabbat = metadata?.isShabbatAlarm ?? false
            let label = metadata?.label ?? String(localized: context.attributes.presentation.alert.title)
            let soundCategory = metadata?.soundCategory ?? ""

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: isShabbat ? "flame.fill" : "alarm.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "D4A548"))

                        Text(label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if !soundCategory.isEmpty {
                            Text(soundCategory)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Spacer()

                        if isShabbat {
                            Text("Shabbat Alarm")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "D4A548"))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: isShabbat ? "flame.fill" : "alarm.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "D4A548"))
            } compactTrailing: {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "D4A548"))
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<AlarmAttributes<ShabbatAlarmMetadata>>) -> some View {
        let metadata = context.attributes.metadata
        let isShabbat = metadata?.isShabbatAlarm ?? false
        let label = metadata?.label ?? String(localized: context.attributes.presentation.alert.title)

        HStack(spacing: 16) {
            Image(systemName: isShabbat ? "flame.fill" : "alarm.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color(hex: "D4A548"))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                if isShabbat {
                    Text("Shabbat Alarm")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "D4A548").opacity(0.8))
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "0D0D2B"),
                    Color(hex: "1A1A40")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Color Hex Extension (Widget-local, matches Theme.swift)

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
