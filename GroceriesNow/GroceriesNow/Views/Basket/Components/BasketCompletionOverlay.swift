import SwiftUI
import UIKit

/// Multi-stage completion celebration shown when the user taps "Complete Basket".
///
/// Animation arc (~900ms):
///   1. Card scales up + fades in. Light haptic tap.
///   2. Ring strokes around the checkmark area (clockwise).
///   3. Checkmark icon pops in with a spring + symbol bounce. Success haptic.
///   4. Title fades up. Then subtitle fades up shortly after.
///
/// The overlay is non-interactive (`allowsHitTesting(false)`) and dismisses
/// itself by parent state change, not by tap.
struct BasketCompletionOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ringProgress: CGFloat = 0
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0

    private let ringDiameter: CGFloat = 92
    private let ringLineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ringAndCheck

                VStack(spacing: 6) {
                    Text("completion.title")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .opacity(titleOpacity)

                    Text("completion.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .opacity(subtitleOpacity)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color("BrandGreen").opacity(0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 30, y: 12)
        }
        .allowsHitTesting(false)
        .onAppear(perform: playSequence)
    }

    private var ringAndCheck: some View {
        ZStack {
            Circle()
                .fill(Color("BrandGreen").opacity(0.12))
                .frame(width: ringDiameter, height: ringDiameter)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    Color("BrandGreen"),
                    style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: ringDiameter - ringLineWidth, height: ringDiameter - ringLineWidth)

            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Color("BrandGreen"))
                .scaleEffect(checkmarkScale)
                .opacity(checkmarkOpacity)
                .symbolEffect(.bounce, options: .nonRepeating, value: checkmarkScale > 0)
        }
        .frame(width: ringDiameter, height: ringDiameter)
    }

    // MARK: - Sequence

    private func playSequence() {
        // Haptics always fire — they're the most accessible feedback and
        // shouldn't be suppressed by reduce-motion (which is a *visual*
        // accommodation, not a sensory one).
        let lightImpact = UIImpactFeedbackGenerator(style: .light)
        lightImpact.prepare()
        lightImpact.impactOccurred()

        if reduceMotion {
            playReducedSequence()
        } else {
            playFullSequence()
        }
    }

    /// Full multi-stage celebration: ring strokes around, checkmark pops with
    /// a spring, title and subtitle fade up sequentially.
    private func playFullSequence() {
        withAnimation(.easeOut(duration: 0.55)) {
            ringProgress = 1
        }

        Task {
            try? await Task.sleep(for: .milliseconds(420))
            await MainActor.run {
                let success = UINotificationFeedbackGenerator()
                success.prepare()
                success.notificationOccurred(.success)

                withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) {
                    checkmarkScale = 1
                    checkmarkOpacity = 1
                }
            }

            try? await Task.sleep(for: .milliseconds(280))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) {
                    titleOpacity = 1
                }
            }

            try? await Task.sleep(for: .milliseconds(120))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) {
                    subtitleOpacity = 1
                }
            }
        }
    }

    /// Reduce-motion variant: skip the staged ring + spring pop. Everything
    /// fades in together, success haptic still fires. The user gets the
    /// completion confirmation without the disorienting motion arc.
    private func playReducedSequence() {
        Task {
            // Brief delay so the haptic and visuals don't land identical.
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                let success = UINotificationFeedbackGenerator()
                success.prepare()
                success.notificationOccurred(.success)

                withAnimation(.easeOut(duration: 0.3)) {
                    ringProgress = 1
                    checkmarkScale = 1
                    checkmarkOpacity = 1
                    titleOpacity = 1
                    subtitleOpacity = 1
                }
            }
        }
    }
}
