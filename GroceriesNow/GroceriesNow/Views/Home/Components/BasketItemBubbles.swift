import SwiftUI

/// Cluster of emoji avatars rotating slowly around the centre of an
/// invisible bounding circle.
///
/// **Layout** — 4 avatars on a circle of `slotRadius`, evenly spaced 90° apart.
/// Slots maintain their 90° angular spacing at all times so avatars never
/// overlap, regardless of how the cluster is rotated.
///
/// **Motion** — the whole cluster rotates around its centre at a slow
/// constant angular velocity. Each avatar travels along the same orbit, just
/// offset by 90° from the next. Reads as a calm carousel, not chaotic.
///
/// **Reusable across surfaces.** Takes a plain `[String]` of emojis. Use
/// `.standard` for the home basket button, `.compact` for list section
/// headers and other tight spaces.
///
/// Respects `accessibilityReduceMotion`: rotation pauses, avatars sit at
/// resting compass-point positions (top / right / bottom / left).
struct BasketItemBubbles: View {

    // MARK: - Public API

    let emojis: [String]
    var size: Size = .standard

    enum Size {
        /// Hero treatment for the floating basket button — ~54pt area, 20pt avatars.
        case standard
        /// Compact treatment for list section headers and other dense spots —
        /// ~36pt area, 14pt avatars.
        case compact

        var containerDiameter: CGFloat {
            switch self {
            case .standard: 62
            case .compact: 44
            }
        }

        var avatarDiameter: CGFloat {
            switch self {
            case .standard: 18
            case .compact: 12
            }
        }

        /// Radius of the orbit each avatar travels along. Sized so adjacent
        /// avatars (90° apart) don't touch, AND so the centre badge has clear
        /// space inside the orbit.
        var slotRadius: CGFloat {
            switch self {
            case .standard: 20
            case .compact: 14
            }
        }

        /// Cluster rotation speed in radians per second. Slow on purpose —
        /// the cluster should feel alive, not catch the eye.
        var spinSpeed: Double {
            switch self {
            case .standard: .pi * 2 / 10  // full revolution every 10 s
            case .compact: .pi * 2 / 12   // slightly slower in dense surfaces
            }
        }

        var emojiFontSize: CGFloat {
            switch self {
            case .standard: 11
            case .compact: 8
            }
        }

        /// Interval between emoji swaps when basket has more than 4 items.
        var rotationInterval: TimeInterval {
            switch self {
            case .standard: 2.8
            case .compact: 3.2
            }
        }

        // MARK: Centre "+N" badge

        var badgeFontSize: CGFloat {
            switch self {
            case .standard: 10
            case .compact: 7
            }
        }

        var badgeHorizontalPadding: CGFloat {
            switch self {
            case .standard: 4
            case .compact: 3
            }
        }

        var badgeVerticalPadding: CGFloat {
            switch self {
            case .standard: 1.5
            case .compact: 1
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let slotCount = 4

    @State private var displayed: [Avatar] = []
    @State private var nextSlotToReplace = 0
    @State private var rotationTask: Task<Void, Never>?

    /// Each visible avatar slot. `slot` (0–3) drives the per-avatar phase
    /// offsets so they never move in lockstep. `id` is fresh on every swap
    /// so SwiftUI's ForEach fires the transition.
    private struct Avatar: Identifiable {
        let id = UUID()
        let emoji: String
        let slot: Int
    }

    var body: some View {
        Group {
            if reduceMotion {
                staticContainer
            } else {
                animatedContainer
            }
        }
        // Invisible bounding box — avatars float in this rect with no visible
        // wrapper. The surrounding view (basket button, list row, etc.)
        // provides the visual frame.
        .frame(width: size.containerDiameter, height: size.containerDiameter)
        .onAppear {
            initialiseDisplayed()
            startRotation()
        }
        .onDisappear {
            rotationTask?.cancel()
        }
        // Reinitialise when emoji set changes — caller may pass a different
        // list (e.g. basket changes). Guarded so identical re-renders are no-ops.
        .onChange(of: emojis) { _, _ in
            initialiseDisplayed()
            startRotation()
        }
    }

    // MARK: - Animated container (full motion)

    private var animatedContainer: some View {
        TimelineView(.animation) { context in
            // Cluster's current rotation, in radians. Wrapped to keep numbers
            // small over long sessions even though `cos`/`sin` accept any value.
            let phase = context.date.timeIntervalSinceReferenceDate * size.spinSpeed
            ZStack {
                ForEach(displayed) { avatar in
                    avatarView(for: avatar)
                        .offset(slotPosition(for: avatar.slot, spin: phase))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                // Centre badge: stays put while avatars spin around it.
                centreBadge
            }
        }
    }

    // MARK: - Static container (reduce-motion fallback)

    private var staticContainer: some View {
        ZStack {
            ForEach(displayed) { avatar in
                avatarView(for: avatar)
                    .offset(slotPosition(for: avatar.slot, spin: 0))
                    .transition(.scale.combined(with: .opacity))
            }
            centreBadge
        }
    }

    // MARK: - Centre "+N" badge

    /// Shown when the basket has more items than the 4 visible slots — it
    /// tells the user "the cluster is a sample, there are this many more".
    /// Sits dead-centre in the orbit so the cluster reads as orbits-around-a-hub.
    @ViewBuilder
    private var centreBadge: some View {
        let hidden = max(0, emojis.count - slotCount)
        if hidden > 0 {
            Text("+\(hidden)")
                .font(.system(size: size.badgeFontSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, size.badgeHorizontalPadding)
                .padding(.vertical, size.badgeVerticalPadding)
                .background(Color.accentColor, in: Capsule())
                .contentTransition(.numericText(value: Double(hidden)))
                .animation(.taplistTransition, value: hidden)
        }
    }

    // MARK: - Single avatar

    private func avatarView(for avatar: Avatar) -> some View {
        Text(avatar.emoji)
            .font(.system(size: size.emojiFontSize))
            .frame(width: size.avatarDiameter, height: size.avatarDiameter)
            .background {
                Circle().fill(Color("CardBackground"))
            }
            .overlay {
                Circle().strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 0.5)
    }

    // MARK: - Position math

    /// Orbital position of an avatar around the bubble centre. The slot's
    /// resting angle (0 = top, 1 = right, 2 = bottom, 3 = left) is offset by
    /// `spin` so the whole cluster rotates together — relative spacing
    /// between avatars stays at exactly 90°, so they can never overlap.
    private func slotPosition(for slot: Int, spin: Double) -> CGSize {
        let restingAngle = (Double(slot) * 2.0 * .pi / Double(slotCount)) - .pi / 2
        let angle = restingAngle + spin
        let x = cos(angle) * size.slotRadius
        let y = sin(angle) * size.slotRadius
        return CGSize(width: x, height: y)
    }

    // MARK: - State management

    private func initialiseDisplayed() {
        let take = min(slotCount, emojis.count)
        displayed = (0..<take).map { i in
            Avatar(emoji: emojis[i], slot: i)
        }
        nextSlotToReplace = 0
    }

    private func startRotation() {
        rotationTask?.cancel()
        // Only rotate when there's something not currently shown to rotate to.
        guard !reduceMotion, emojis.count > slotCount else { return }

        let interval = size.rotationInterval
        rotationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                rotateOneAvatar()
            }
        }
    }

    /// Replace the avatar in slot `nextSlotToReplace` with the next emoji not
    /// currently visible, then advance the round-robin pointer.
    private func rotateOneAvatar() {
        guard emojis.count > slotCount else { return }

        let visibleEmojis = Set(displayed.map(\.emoji))
        guard let next = emojis.first(where: { !visibleEmojis.contains($0) }) else { return }

        let slot = nextSlotToReplace
        guard let index = displayed.firstIndex(where: { $0.slot == slot }) else { return }

        // Replace with a fresh Avatar (new UUID) so ForEach treats it as
        // remove+insert and fires the transition on both sides.
        withAnimation(.easeInOut(duration: 0.7)) {
            displayed[index] = Avatar(emoji: next, slot: slot)
        }

        nextSlotToReplace = (nextSlotToReplace + 1) % slotCount
    }
}
