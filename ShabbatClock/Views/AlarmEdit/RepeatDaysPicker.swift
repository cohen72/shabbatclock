import SwiftUI

/// A picker for selecting repeat days of the week.
struct RepeatDaysPicker: View {
    @Binding var selectedDays: [Int]

    private let days = [
        (0, "S", "Sunday"),
        (1, "M", "Monday"),
        (2, "T", "Tuesday"),
        (3, "W", "Wednesday"),
        (4, "T", "Thursday"),
        (5, "F", "Friday"),
        (6, "S", "Saturday")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repeat")
                .font(AppFont.caption(12))
                .foregroundStyle(.textSecondary)

            HStack(spacing: 8) {
                ForEach(days, id: \.0) { day in
                    DayButton(
                        letter: day.1,
                        fullName: day.2,
                        isSelected: selectedDays.contains(day.0),
                        isShabbat: day.0 == 6
                    ) {
                        toggleDay(day.0)
                    }
                }
            }

            // Quick select options
            HStack(spacing: 12) {
                QuickSelectButton(title: "Weekdays") {
                    selectedDays = [1, 2, 3, 4, 5]
                }

                QuickSelectButton(title: "Weekends") {
                    selectedDays = [0, 6]
                }

                QuickSelectButton(title: "Every day") {
                    selectedDays = [0, 1, 2, 3, 4, 5, 6]
                }

                QuickSelectButton(title: "Clear") {
                    selectedDays = []
                }
            }
        }
    }

    private func toggleDay(_ day: Int) {
        if selectedDays.contains(day) {
            selectedDays.removeAll { $0 == day }
        } else {
            selectedDays.append(day)
            selectedDays.sort()
        }
    }
}

// MARK: - Day Button

struct DayButton: View {
    let letter: String
    let fullName: String
    let isSelected: Bool
    let isShabbat: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(AppFont.body(14))
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(foregroundColor)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(backgroundColor)
                        .overlay(
                            Circle()
                                .strokeBorder(borderColor, lineWidth: isShabbat && !isSelected ? 1.5 : 0)
                        )
                )
        }
        .accessibilityLabel("\(fullName), \(isSelected ? "selected" : "not selected")")
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        }
        return isShabbat ? .goldAccent : .textSecondary
    }

    private var backgroundColor: Color {
        if isSelected {
            return isShabbat ? .goldAccent : .accentPurple
        }
        return .white.opacity(0.1)
    }

    private var borderColor: Color {
        isShabbat ? .goldAccent.opacity(0.5) : .clear
    }
}

// MARK: - Quick Select Button

struct QuickSelectButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.caption(11))
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
        }
    }
}

// MARK: - Full Screen Repeat Picker (for navigation)

struct RepeatDaysPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDays: [Int]

    private let days = [
        (0, "Sunday"),
        (1, "Monday"),
        (2, "Tuesday"),
        (3, "Wednesday"),
        (4, "Thursday"),
        (5, "Friday"),
        (6, "Saturday (Shabbat)")
    ]

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.textSecondary)

                    Spacer()

                    Text("Repeat")
                        .font(AppFont.header(18))
                        .foregroundStyle(.textPrimary)

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.accentPurple)
                    .fontWeight(.semibold)
                }
                .padding()

                // Days list
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(days, id: \.0) { day in
                            Button {
                                toggleDay(day.0)
                            } label: {
                                HStack {
                                    Text(day.1)
                                        .font(AppFont.body())
                                        .foregroundStyle(day.0 == 6 ? .goldAccent : .textPrimary)

                                    Spacer()

                                    if selectedDays.contains(day.0) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.accentPurple)
                                            .fontWeight(.semibold)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.05))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // Summary
                    if !selectedDays.isEmpty {
                        Text(repeatSummary)
                            .font(AppFont.caption(13))
                            .foregroundStyle(.textSecondary)
                            .padding(.top, 16)
                    }
                }
            }
        }
    }

    private func toggleDay(_ day: Int) {
        if selectedDays.contains(day) {
            selectedDays.removeAll { $0 == day }
        } else {
            selectedDays.append(day)
            selectedDays.sort()
        }
    }

    private var repeatSummary: String {
        if selectedDays.count == 7 {
            return "Repeats every day"
        }
        if Set(selectedDays) == Set([1, 2, 3, 4, 5]) {
            return "Repeats on weekdays"
        }
        if Set(selectedDays) == Set([0, 6]) {
            return "Repeats on weekends"
        }
        return "Repeats on selected days"
    }
}

// MARK: - Preview

#Preview("Inline Picker") {
    ZStack {
        LinearGradient.nightSky
            .ignoresSafeArea()

        RepeatDaysPicker(selectedDays: .constant([6]))
            .padding()
    }
}

#Preview("Full Screen Picker") {
    RepeatDaysPickerView(selectedDays: .constant([0, 6]))
}
