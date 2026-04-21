import SwiftUI
import SwiftData
import AVFoundation

/// Records a custom alarm sound (up to 30 seconds), lets the user trim and name it,
/// then saves it to the App Group's Library/Sounds directory.
///
/// Presented as a sheet. On successful save, calls `onSaved(fileName:)` so the caller
/// can update the parent alarm's sound selection.
struct SoundRecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Called with the SwiftData id of the freshly saved CustomSound when the user saves.
    var onSaved: ((PersistentIdentifier) -> Void)?

    @State private var recorder = AudioRecordingManager.shared
    @State private var soundName: String = ""
    @State private var showPermissionDenied = false
    @State private var isSaving = false

    private let maxNameChars = 24

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        timerSection
                            .padding(.top, 24)

                        Text("Record up to 30 seconds")
                            .font(AppFont.caption(13))
                            .foregroundStyle(.textSecondary)

                        if recorder.lastRecordedUrl != nil && !recorder.isRecording {
                            trimmerAndNameSection
                        }

                        actionButtons
                            .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        recorder.cancelRecording()
                        dismiss()
                    }
                }
            }
            .onAppear {
                recorder.reset()
            }
            .alert("Microphone Access", isPresented: $showPermissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enable microphone access in Settings to record a custom alarm sound.")
            }
        }
        .applyLanguageOverride(AppLanguage.current)
    }

    // MARK: - Subviews

    private var titleKey: LocalizedStringKey {
        if recorder.isRecording {
            return "Recording…"
        } else if recorder.lastRecordedUrl != nil {
            return "Name Your Sound"
        } else {
            return "New Custom Sound"
        }
    }

    private var timerSection: some View {
        ZStack {
            Circle()
                .stroke(Color.goldAccent.opacity(0.12), lineWidth: 6)
                .frame(width: 240, height: 240)

            if recorder.isRecording {
                Circle()
                    .trim(from: 0, to: CGFloat(recorder.recordingDuration / AudioRecordingManager.maxDuration))
                    .stroke(
                        Color.goldAccent,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 240, height: 240)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: recorder.recordingDuration)
            }

            VStack(spacing: 12) {
                Text(formattedDuration)
                    .font(.system(size: 42, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.textPrimary)

                if recorder.isRecording {
                    LiveAudioMeter(level: recorder.audioLevel)
                        .frame(height: 18)
                } else if recorder.lastRecordedUrl != nil {
                    Button {
                        if recorder.isPlayingPreview {
                            recorder.stopPreview()
                        } else {
                            recorder.playPreview()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: recorder.isPlayingPreview ? "stop.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(recorder.isPlayingPreview ? "Stop" : "Preview")
                                .font(AppFont.body(13))
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.goldAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.goldAccent.opacity(0.12))
                        )
                    }
                }
            }
        }
    }

    private var trimmerAndNameSection: some View {
        VStack(spacing: 20) {
            AudioTrimmer(
                duration: recorder.recordingDuration,
                levels: recorder.levels,
                startTime: Binding(
                    get: { recorder.trimStartTime },
                    set: { recorder.trimStartTime = $0 }
                ),
                endTime: Binding(
                    get: { recorder.trimEndTime },
                    set: { recorder.trimEndTime = $0 }
                )
            )
            .frame(height: 80)

            VStack(alignment: .leading, spacing: 8) {
                Text("NAME")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.textSecondary)

                HStack {
                    TextField("My Melody", text: $soundName)
                        .font(AppFont.body(16))
                        .foregroundStyle(.textPrimary)
                        .submitLabel(.done)
                        .onChange(of: soundName) { _, newValue in
                            if newValue.count > maxNameChars {
                                soundName = String(newValue.prefix(maxNameChars))
                            }
                        }
                    Spacer()
                    Text("\(soundName.count)/\(maxNameChars)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.textSecondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.surfaceCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.surfaceBorder, lineWidth: 0.5)
                        )
                )
            }
        }
    }

    private var actionButtons: some View {
        Group {
            if recorder.isRecording {
                Button(action: stopRecording) {
                    recordButtonContent(isRecording: true)
                }
            } else if recorder.lastRecordedUrl == nil {
                Button(action: requestAndStartRecording) {
                    recordButtonContent(isRecording: false)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        recorder.cancelRecording()
                        soundName = ""
                    } label: {
                        Text("Retake")
                            .font(AppFont.body(16))
                            .fontWeight(.semibold)
                            .foregroundStyle(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.surfaceCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.surfaceBorder, lineWidth: 0.5)
                                    )
                            )
                    }

                    Button(action: saveRecording) {
                        HStack {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save")
                                    .font(AppFont.body(16))
                                    .fontWeight(.bold)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    soundName.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? Color.goldAccent.opacity(0.35)
                                        : Color.goldAccent
                                )
                                .shadow(
                                    color: Color.goldAccent.opacity(
                                        soundName.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 0.35
                                    ),
                                    radius: 12, y: 4
                                )
                        )
                    }
                    .disabled(soundName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func recordButtonContent(isRecording: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.goldAccent : Color.red)
                .frame(width: 76, height: 76)
                .shadow(
                    color: (isRecording ? Color.goldAccent : .red).opacity(0.35),
                    radius: 10
                )

            if isRecording {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white)
                    .frame(width: 24, height: 24)
            } else {
                Circle()
                    .fill(.white)
                    .frame(width: 30, height: 30)
            }
        }
        .scaleEffect(isRecording ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
    }

    // MARK: - Actions

    private func requestAndStartRecording() {
        Task {
            let status = AVAudioApplication.shared.recordPermission
            switch status {
            case .granted:
                _ = await recorder.startRecording()
            case .denied:
                showPermissionDenied = true
            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        if granted {
                            _ = await recorder.startRecording()
                        } else {
                            showPermissionDenied = true
                        }
                    }
                }
            @unknown default:
                break
            }
        }
    }

    private func stopRecording() {
        recorder.stopRecording()
    }

    private func saveRecording() {
        let trimmedName = soundName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        Task {
            if let fileName = await recorder.saveRecording() {
                let custom = CustomSound(
                    name: trimmedName,
                    fileName: fileName,
                    duration: recorder.trimEndTime - recorder.trimStartTime
                )
                modelContext.insert(custom)
                try? modelContext.save()
                isSaving = false
                onSaved?(custom.persistentModelID)
                dismiss()
            } else {
                isSaving = false
            }
        }
    }

    // MARK: - Formatting

    private var formattedDuration: String {
        let value: TimeInterval
        if recorder.isRecording {
            value = recorder.recordingDuration
        } else if recorder.lastRecordedUrl != nil {
            value = recorder.trimEndTime - recorder.trimStartTime
        } else {
            value = 0
        }
        let seconds = Int(value)
        let tenths = Int((value * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "00:%02d.%d", seconds, tenths)
    }
}

/// Simple animated capsule meter that responds to live audio level (0.0–1.0).
private struct LiveAudioMeter: View {
    let level: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<15, id: \.self) { _ in
                let jitter = CGFloat.random(in: 0.55...1.0)
                let height = max(4.0, 30.0 * level * jitter)
                Capsule()
                    .fill(Color.goldAccent)
                    .frame(width: 3, height: height)
                    .animation(.spring(response: 0.15, dampingFraction: 0.5), value: level)
            }
        }
    }
}
