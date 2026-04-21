import SwiftUI

/// Interactive waveform trimmer with draggable start/end handles.
/// Active selection bars are drawn in the gold accent; unselected bars are dimmed.
struct AudioTrimmer: View {
    let duration: TimeInterval
    let levels: [CGFloat]
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval

    @State private var leftOffset: CGFloat = 0
    @State private var rightOffset: CGFloat = 0
    @State private var initialized = false

    private let handleWidth: CGFloat = 16
    private let handleBuffer: CGFloat = 8
    private let minSelectionWidth: CGFloat = 40
    private let barHeight: CGFloat = 60

    private var isTrimmed: Bool {
        startTime > 0.1 || abs(endTime - duration) > 0.1
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let usableWidth = totalWidth - (handleBuffer * 2)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.surfaceBorder, lineWidth: 1)
                    .frame(width: totalWidth, height: barHeight + 16)

                WaveformBars(
                    levels: levels,
                    selectionStart: usableWidth > 0 ? leftOffset / usableWidth : 0,
                    selectionEnd: usableWidth > 0 ? rightOffset / usableWidth : 1
                )
                .frame(width: usableWidth, height: barHeight)
                .offset(x: handleBuffer)

                Rectangle()
                    .stroke(Color.goldAccent, lineWidth: 2)
                    .frame(
                        width: max(0, rightOffset - leftOffset),
                        height: barHeight
                    )
                    .offset(x: handleBuffer + leftOffset)

                TrimHandle()
                    .offset(x: handleBuffer + leftOffset - handleWidth / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newOffset = max(
                                    0,
                                    min(value.location.x - handleBuffer, rightOffset - minSelectionWidth)
                                )
                                leftOffset = newOffset
                                if usableWidth > 0 {
                                    startTime = Double(newOffset / usableWidth) * duration
                                }
                            }
                    )

                TrimHandle()
                    .offset(x: handleBuffer + rightOffset - handleWidth / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newOffset = min(
                                    usableWidth,
                                    max(value.location.x - handleBuffer, leftOffset + minSelectionWidth)
                                )
                                rightOffset = newOffset
                                if usableWidth > 0 {
                                    endTime = Double(newOffset / usableWidth) * duration
                                }
                            }
                    )
            }
            .frame(width: totalWidth, height: barHeight + 16, alignment: .center)
            .onAppear {
                guard !initialized, duration > 0, usableWidth > 0 else { return }
                leftOffset = CGFloat(startTime / duration) * usableWidth
                rightOffset = CGFloat(endTime / duration) * usableWidth
                initialized = true
            }
            .onChange(of: usableWidth) { _, newWidth in
                guard duration > 0, newWidth > 0 else { return }
                leftOffset = CGFloat(startTime / duration) * newWidth
                rightOffset = CGFloat(endTime / duration) * newWidth
            }
        }
    }
}

private struct WaveformBars: View {
    let levels: [CGFloat]
    let selectionStart: CGFloat
    let selectionEnd: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let barWidth: CGFloat = 2
            let spacing: CGFloat = 2
            let total = max(1, Int(width / (barWidth + spacing)))

            HStack(alignment: .center, spacing: spacing) {
                if levels.isEmpty {
                    ForEach(0..<total, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.goldAccent.opacity(0.15))
                            .frame(width: barWidth, height: 4)
                    }
                } else {
                    let sampled = resample(levels, to: total)
                    ForEach(0..<sampled.count, id: \.self) { i in
                        let progress = CGFloat(i) / CGFloat(total)
                        let inSelection = progress >= selectionStart && progress <= selectionEnd
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.goldAccent.opacity(inSelection ? 1.0 : 0.2))
                            .frame(
                                width: barWidth,
                                height: max(4, sampled[i] * geo.size.height * 0.7)
                            )
                    }
                }
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
    }

    private func resample(_ input: [CGFloat], to count: Int) -> [CGFloat] {
        guard !input.isEmpty, count > 0 else { return [] }
        if input.count == count { return input }
        var output: [CGFloat] = []
        output.reserveCapacity(count)
        for i in 0..<count {
            let center = CGFloat(i) * CGFloat(input.count) / CGFloat(count)
            let idx = min(Int(center), input.count - 1)
            output.append(input[idx])
        }
        return output
    }
}

private struct TrimHandle: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.goldAccent)
                .frame(width: 16, height: 68)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.9))
                .frame(width: 2, height: 20)
        }
        .shadow(color: .black.opacity(0.3), radius: 3)
    }
}
