import SwiftUI

/// Wraps a row with a swipe-to-reveal delete action. Works inside LazyVStack
/// where native `List.swipeActions` is not available. RTL-aware.
struct SwipeToDelete<Content: View>: View {
    @Environment(\.layoutDirection) private var layoutDirection

    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    private let actionWidth: CGFloat = 88
    private let triggerThreshold: CGFloat = 140

    var body: some View {
        let isRTL = layoutDirection == .rightToLeft
        let totalOffset = offset + dragOffset
        // In LTR swipe left reveals action on trailing edge (negative offset).
        // In RTL swipe right reveals action on leading edge (positive offset).
        let revealedAmount = isRTL ? max(0, totalOffset) : max(0, -totalOffset)

        ZStack(alignment: isRTL ? .leading : .trailing) {
            // Delete action background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.red.opacity(0.9))
                .overlay(
                    Button {
                        performDelete()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Delete")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: actionWidth)
                        .frame(maxHeight: .infinity)
                    }
                    .opacity(revealedAmount > 20 ? 1 : 0)
                )
                .opacity(revealedAmount > 0 ? 1 : 0)

            content()
                .offset(x: isRTL ? min(totalOffset, revealedAmount) : max(totalOffset, -revealedAmount))
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .updating($dragOffset) { value, state, _ in
                            let translation = value.translation.width
                            // Only allow swipe in the correct direction
                            if isRTL {
                                state = max(0, min(translation + offset, actionWidth * 2)) - offset
                            } else {
                                state = min(0, max(translation + offset, -actionWidth * 2)) - offset
                            }
                        }
                        .onEnded { value in
                            let finalOffset = offset + value.translation.width
                            let reveal = isRTL ? finalOffset : -finalOffset

                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if reveal >= triggerThreshold {
                                    // Full swipe triggers delete
                                    offset = isRTL ? UIScreen.main.bounds.width : -UIScreen.main.bounds.width
                                } else if reveal >= actionWidth / 2 {
                                    offset = isRTL ? actionWidth : -actionWidth
                                } else {
                                    offset = 0
                                }
                            }

                            if reveal >= triggerThreshold {
                                // Delay to let animation play
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    performDelete()
                                }
                            }
                        }
                )
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: offset)
    }

    private func performDelete() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        onDelete()
    }
}
