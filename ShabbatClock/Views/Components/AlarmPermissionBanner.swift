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
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Alarms Can't Ring")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("Enable alarms in Settings to let Shabbat Clock wake you")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.6))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
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
