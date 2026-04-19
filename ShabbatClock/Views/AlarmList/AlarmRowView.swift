import SwiftUI

/// A row displaying a single alarm in the list.
/// Visual differentiation:
/// - Regular alarm: plain card
/// - Zman alarm: subtle "Zman" pill badge
/// - Shabbat alarm: gold left border + "✡ Shabbat" pill
struct AlarmRowView: View {
  @Bindable var alarm: Alarm
  @Environment(AlarmKitService.self) private var alarmService
  var onToggle: ((Bool) -> Void)?
  
  /// Whether this alarm is linked to a zman
  private var isZmanAlarm: Bool {
    alarm.zmanTypeRawValue != nil
  }
  
  /// Whether this alarm has Shabbat styling (any repeat day includes Saturday)
  private var isShabbatStyled: Bool {
    alarm.repeatDays.contains(6)
  }
  
  /// Descriptive label for zman alarms (e.g., "Dawn · 5 min before")
  private var zmanDescriptionLabel: String? {
    guard let rawValue = alarm.zmanTypeRawValue,
          let zmanType = ZmanimService.ZmanType(rawValue: rawValue) else { return nil }
    let name = zmanType.englishName
    if let minutes = alarm.zmanMinutesBefore, minutes > 0 {
      return String(format: AppLanguage.localized("%@ · %d min before"), name, minutes)
    }
    return String(format: AppLanguage.localized("%@ · At zman time"), name)
  }
  
  var body: some View {
    if alarm.isDeleted {
      EmptyView()
    } else {
      rowContent
    }
  }
  
  private var rowContent: some View {
    HStack(spacing: 0) {
      // Gold left border for Shabbat alarms
      if isShabbatStyled {
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.goldAccent)
          .frame(width: 3)
          .padding(.vertical, 8)
          .padding(.trailing, 12)
      }
      
      VStack(alignment: .leading, spacing: 6) {
        // Time
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(alarm.timeString)
            .font(.system(size: 56, weight: .thin, design: .default))
            .monospacedDigit()
            .foregroundStyle(alarm.isEnabled ? .textPrimary : .textSecondary.opacity(0.6))
          
          Text(alarm.periodString)
            .font(.system(size: 22, weight: .thin, design: .default))
            .foregroundStyle(.textSecondary.opacity(alarm.isEnabled ? 0.8 : 0.4))
        }
        
        // Label (or zman description) + duration
        HStack(spacing: 6) {
          if let zmanDesc = zmanDescriptionLabel {
            Text(zmanDesc)
              .font(.system(size: 14, weight: .regular, design: .default))
              .foregroundStyle(.textSecondary.opacity(alarm.isEnabled ? 0.85 : 0.4))
          } else {
            Text(alarm.label)
              .font(.system(size: 14, weight: .regular, design: .default))
              .foregroundStyle(.textSecondary.opacity(alarm.isEnabled ? 0.85 : 0.4))
          }
          
          HStack(spacing: 3) {
            Image(systemName: "bell.fill")
              .font(.system(size: 9))
            Text(durationLabel)
              .font(.system(size: 11, weight: .medium, design: .rounded))
              .monospacedDigit()
          }
          .foregroundStyle(.goldAccent.opacity(alarm.isEnabled ? 0.75 : 0.35))
        }
        
        // Schedule + type badge
        HStack(spacing: 8) {
          Text(scheduleLabel)
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundStyle(.goldAccent.opacity(alarm.isEnabled ? 0.8 : 0.4))
          
          // Type pill badge
          if isShabbatStyled {
            alarmTypePill(text: String(localized: "Shabbat"), systemIcon: "flame.fill", isShabbat: true)
          } else if isZmanAlarm {
            alarmTypePill(text: String(localized: "Zman"), icon: "☀", isShabbat: false)
          }
        }
      }
      
      Spacer(minLength: 12)
      
      // Toggle
      Toggle("", isOn: $alarm.isEnabled)
        .labelsHidden()
        .tint(isShabbatStyled ? .goldAccent : .accentPurple)
        .onChange(of: alarm.isEnabled) { _, newValue in
          onToggle?(newValue)
        }
    }
    .padding(.horizontal, isShabbatStyled ? 12 : 20)
    .padding(.vertical, 14)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(cardFillColor)
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(cardBorderColor, lineWidth: 0.5)
        )
    )
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: alarm.isEnabled)
  }
  
  // MARK: - Card Colors
  
  private var cardFillColor: Color {
    if isShabbatStyled && alarm.isEnabled {
      return Color.goldAccent.opacity(0.05)
    }
    return alarm.isEnabled ? Color.surfaceCard : Color.surfaceSubtle
  }
  
  private var cardBorderColor: Color {
    if isShabbatStyled && alarm.isEnabled {
      return Color.goldAccent.opacity(0.3)
    }
    return Color.surfaceBorder.opacity(alarm.isEnabled ? 1 : 0.5)
  }
  
  // MARK: - Type Pill
  
  private func alarmTypePill(text: String, icon: String? = nil, systemIcon: String? = nil, isShabbat: Bool) -> some View {
    HStack(spacing: 3) {
      if let systemIcon {
        Image(systemName: systemIcon)
          .font(.system(size: 8))
      } else if let icon {
        Text(icon)
          .font(.system(size: 8))
      }
      Text(text)
        .font(.system(size: 10, weight: .medium))
    }
    .foregroundStyle(isShabbat ? .goldAccent : .textSecondary)
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(
      Capsule()
        .fill(isShabbat ? Color.goldAccent.opacity(0.15) : Color.surfaceSubtle)
    )
  }
  
  // MARK: - Computed Labels
  
  private var durationLabel: String {
    let seconds = alarm.alarmDurationSeconds
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    return "\(minutes)m"
  }
  
  private var scheduleLabel: String {
    // Repeat days take precedence (e.g., "Tue, Thu, Sat")
    if !alarm.repeatDays.isEmpty {
      return alarm.repeatDaysString
    }
    // One-time alarm — show relative date
    let locale = AppLanguage.current.effectiveLocale
    let calendar = Calendar.current
    let now = Date()
    guard let fireDate = alarm.nextFireDate(from: now) else {
      // Disabled alarm — still show a schedule hint
      return oneTimeFallbackLabel(locale: locale, calendar: calendar, now: now)
    }
    return relativeDateLabel(for: fireDate, now: now, calendar: calendar, locale: locale)
  }
  
  private func oneTimeFallbackLabel(locale: Locale, calendar: Calendar, now: Date) -> String {
    var components = calendar.dateComponents([.year, .month, .day], from: now)
    components.hour = alarm.hour
    components.minute = alarm.minute
    guard let candidate = calendar.date(from: components) else {
      return String(localized: "Once")
    }
    let target = candidate <= now ? calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate : candidate
    return relativeDateLabel(for: target, now: now, calendar: calendar, locale: locale)
  }
  
  private func relativeDateLabel(for date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
    if calendar.isDateInToday(date) {
      return String(localized: "Today")
    }
    if calendar.isDateInTomorrow(date) {
      return String(localized: "Tomorrow")
    }
    let formatter = DateFormatter()
    formatter.locale = locale
    if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day, days < 7 {
      formatter.setLocalizedDateFormatFromTemplate("EEEE")
    } else {
      formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
    }
    return formatter.string(from: date)
  }
}

// MARK: - Compact Row (for smaller displays)

struct AlarmRowCompact: View {
  @Bindable var alarm: Alarm
  
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(alarm.timeString)
            .font(AppFont.header(22))
            .foregroundStyle(alarm.isEnabled ? .textPrimary : .textSecondary)
          
          Text(alarm.periodString)
            .font(AppFont.caption(11))
            .foregroundStyle(.textSecondary)
        }
        
        Text(alarm.label)
          .font(AppFont.caption(12))
          .foregroundStyle(.textSecondary)
      }
      
      Spacer()
      
      Toggle("", isOn: $alarm.isEnabled)
        .labelsHidden()
        .tint(.accentPurple)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .glassMorphic(cornerRadius: 12, opacity: alarm.isEnabled ? 0.06 : 0.03)
  }
}

// MARK: - Preview

#Preview {
  ZStack {
    LinearGradient.nightSky
      .ignoresSafeArea()
    
    VStack(spacing: 12) {
      AlarmRowView(
        alarm: Alarm(
          hour: 7,
          minute: 30,
          isEnabled: true,
          label: "Shacharis",
          repeatDays: [6]
        )
      )
      
      AlarmRowView(
        alarm: Alarm(
          hour: 9,
          minute: 0,
          isEnabled: false,
          label: "Late Shacharis",
          repeatDays: []
        )
      )
    }
    .padding()
  }
  .environment(AlarmKitService.shared)
}
