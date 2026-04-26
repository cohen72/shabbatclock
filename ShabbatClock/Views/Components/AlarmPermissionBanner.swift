import SwiftUI

/// Soft-degrade banner shown when the user has denied AlarmKit permission.
/// Tapping opens iOS Settings so the user can re-enable alarms.
///
/// Used across MainClockView, AlarmListView, and ZmanimView so the state
/// is never ambiguous — alarms stored in SwiftData remain visible but
/// won't fire until permission is granted.
struct AlarmPermissionBanner: View {
    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.goldAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Alarm Permission Needed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("Tap to enable in Shabbat Clock Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.textSecondary.opacity(0.5))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.goldAccent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.goldAccent.opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        LinearGradient.nightSky.ignoresSafeArea()
        AlarmPermissionBanner()
            .padding()
    }
}
