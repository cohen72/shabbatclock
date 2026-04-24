import SwiftUI
import SwiftData

/// Pre-Shabbat checklist shown after the user taps the Friday reminder notification,
/// or accessible manually from elsewhere. Helps the user confirm their alarms are
/// set and their phone is configured for the cleanest Shabbat alarm experience.
///
/// State persists through `@AppStorage` and resets each Friday (new week).
struct ShabbatChecklistView: View {
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \Alarm.hour) private var allAlarms: [Alarm]
  
  /// Tracked checks. Each persists across launches; reset on new Friday.
  @AppStorage("shabbatChecklist.silentMode") private var silentModeChecked = false
  @AppStorage("shabbatChecklist.vibrationOff") private var vibrationOffChecked = false
  @AppStorage("shabbatChecklist.alarmsReviewed") private var alarmsReviewedChecked = false
  
  /// The Friday-of-the-week date string this checklist was last reset for.
  /// Compared on appear; if it's a new week, all checks are cleared.
  @AppStorage("shabbatChecklist.lastResetWeek") private var lastResetWeek = ""
  
  @State private var showingRingSetup = false
  
  /// Enabled alarms scheduled to fire during this Shabbat window
  /// (candle-lighting → havdalah). Falls back to a 48-hour window if
  /// Shabbat times aren't available.
  private var upcomingAlarms: [Alarm] {
    let now = Date()
    let zmanimService = ZmanimService.shared
    let windowEnd: Date
    if let havdalah = zmanimService.havdalahTime, havdalah > now {
      windowEnd = havdalah
    } else {
      windowEnd = now.addingTimeInterval(48 * 3600)
    }
    return allAlarms.filter { alarm in
      alarm.isEnabled
      && (alarm.nextFireDate(from: now).map { $0 <= windowEnd } ?? false)
    }
  }
  
  private var allChecked: Bool {
    silentModeChecked && vibrationOffChecked && alarmsReviewedChecked
  }
  
  var body: some View {
    NavigationStack {
      ZStack {
        LinearGradient.nightSky
          .ignoresSafeArea()
        
        ScrollView {
          VStack(spacing: 20) {
            header
            checklistCard
            if allChecked {
              allSetCard
                .transition(.asymmetric(
                  insertion: .scale(scale: 0.9).combined(with: .opacity),
                  removal: .opacity
                ))
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 8)
          .padding(.bottom, 40)
          .animation(.spring(response: 0.45, dampingFraction: 0.75), value: allChecked)
        }
      }
      .navigationTitle("Ready for Shabbat?")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            dismiss()
          }
        }
      }
    }
    .sheet(isPresented: $showingRingSetup) {
      NavigationStack {
        RingSetupView(mode: .standalone)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Done") { showingRingSetup = false }
                .foregroundStyle(.accentPurple)
            }
          }
      }
      .applyLanguageOverride(AppLanguage.current)
    }
    .onAppear {
      resetIfNewWeek()
    }
  }
  
  // MARK: - Header
  
  private var header: some View {
    VStack(spacing: 10) {
      Image(systemName: "flame.fill")
        .font(.system(size: 40))
        .foregroundStyle(.goldAccent)
      
      Text("A few quick checks")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.textPrimary)
      
      Text("Make sure everything is ready so Shabbat starts smoothly.")
        .font(.system(size: 13))
        .foregroundStyle(.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
    }
    .padding(.top, 8)
  }
  
  // MARK: - Checklist
  
  private var checklistCard: some View {
    VStack(spacing: 0) {
      checklistRow(
        isChecked: $silentModeChecked,
        title: "Silent Mode is on",
        subtitle: "Flip the switch on the side of your iPhone."
      )
      
      Divider().overlay(Color.surfaceBorder).padding(.leading, 52)
      
      checklistRow(
        isChecked: $vibrationOffChecked,
        title: "Vibration is off",
        subtitle: "Settings → Sounds & Haptics → Don't Play in Silent Mode.",
        trailingButton: AnyView(
          Button("How?") {
            showingRingSetup = true
          }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.accentPurple)
        )
      )
      
      Divider().overlay(Color.surfaceBorder).padding(.leading, 52)
      
      checklistRow(
        isChecked: $alarmsReviewedChecked,
        title: "Review your alarms",
        subtitle: upcomingAlarms.isEmpty
        ? "You have no alarms set for this Shabbat."
        : "You have \(upcomingAlarms.count) alarm\(upcomingAlarms.count == 1 ? "" : "s") set for this Shabbat."
      )
    }
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(Color.surfaceBorder, lineWidth: 0.5)
    )
  }
  
  private func checklistRow(
    isChecked: Binding<Bool>,
    title: LocalizedStringKey,
    subtitle: LocalizedStringKey,
    trailingButton: AnyView? = nil
  ) -> some View {
    Button {
      isChecked.wrappedValue.toggle()
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: isChecked.wrappedValue ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 22))
          .foregroundStyle(isChecked.wrappedValue ? .green : .textSecondary.opacity(0.5))
          .frame(width: 28)
          .padding(.top, 1)
        
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.textPrimary)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        
        Spacer(minLength: 0)
        
        if let trailingButton {
          trailingButton
        }
      }
      .padding(14)
      .background(Color.surfaceCard)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
  
  // MARK: - Upcoming alarms preview
  
  @ViewBuilder
  private var upcomingAlarmsCard: some View {
    if !upcomingAlarms.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "alarm.fill")
            .font(.system(size: 13))
            .foregroundStyle(.accentPurple)
          Text("Your alarms")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.textPrimary)
        }
        
        VStack(spacing: 6) {
          ForEach(upcomingAlarms.prefix(5)) { alarm in
            HStack {
              Text(alarm.label)
                .font(.system(size: 13))
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
              Spacer()
              Text(alarm.formattedTime)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.textPrimary)
            }
            .padding(.vertical, 2)
          }
          if upcomingAlarms.count > 5 {
            Text("+ \(upcomingAlarms.count - 5) more")
              .font(.system(size: 11))
              .foregroundStyle(.textSecondary)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.top, 2)
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .themeCard(cornerRadius: 12)
    }
  }
  
  // MARK: - All set!
  
  private var allSetCard: some View {
    VStack(spacing: 8) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 36))
        .foregroundStyle(.green)
      
      Text("You're all set!")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.textPrimary)
      
      Text("Shabbat Shalom 🕯️")
        .font(.system(size: 13))
        .foregroundStyle(.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.green.opacity(0.08))
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(Color.green.opacity(0.3), lineWidth: 0.5)
        )
    )
  }
  
  // MARK: - Weekly reset
  
  /// Reset all checks if this is a new "Shabbat week" (different Friday than last reset).
  /// Uses ISO week-of-year + year to identify the week.
  private func resetIfNewWeek() {
    let calendar = Calendar.current
    let now = Date()
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
    let weekKey = "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    
    if weekKey != lastResetWeek {
      silentModeChecked = false
      vibrationOffChecked = false
      alarmsReviewedChecked = false
      lastResetWeek = weekKey
    }
  }
}

// MARK: - Preview

#Preview {
  ShabbatChecklistView()
    .modelContainer(for: Alarm.self, inMemory: true)
}
