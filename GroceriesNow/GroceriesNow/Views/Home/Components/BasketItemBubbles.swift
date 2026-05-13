import SwiftUI

/// Cluster of emoji avatars rotating slowly around the centre of an
/// invisible bounding circle.
///
/// **Layout** — up to 4 avatars on a circle of `dynamicSlotRadius`, evenly
/// spaced around the full 360°. With fewer avatars the spacing stays balanced
/// (2 → 180° apart, 3 → 120° apart, 4 → 90° apart). The avatar diameter and
/// orbit radius both scale down as the cluster fills up, so a single large
/// emoji gradually shrinks into a full four-avatar carousel.
///
/// **Motion** — the whole cluster rotates around its centre at a slow
/// constant angular velocity. Each avatar travels along the same orbit, just
/// offset by 360°/n from the next. Reads as a calm carousel, not chaotic.
///
/// **Reusable across surfaces.** Takes a plain `[String]` of emojis. Use
/// `.standard` for the home basket button, `.compact` for list section
/// headers and other tight spaces.
///
/// Respects `accessibilityReduceMotion`: rotation pauses, avatars sit at
/// resting positions.
struct BasketItemBubbles: View {

    // MARK: - Public API

    let emojis: [String]
    var size: Size = .standard
    /// Set to `false` to freeze the spin in place — useful while a navigation
    /// transition is in progress so the constant TimelineView invalidation
    /// doesn't compete with the transition renderer.
    var isAnimating: Bool = true

    enum Size {
        /// Hero treatment for the floating basket button — ~62pt area, 18pt avatars (at 4 items).
        case standard
        /// Compact treatment for list section headers and other dense spots —
        /// ~44pt area, 12pt avatars (at 4 items).
        case compact

        var containerDiameter: CGFloat {
            switch self {
            case .standard: 72
            case .compact: 44
            }
        }

        // The values below are the "full cluster" (4-avatar) baselines.
        // Actual runtime sizes are computed dynamically in BasketItemBubbles.

        var avatarDiameter: CGFloat {
            switch self {
            case .standard: 21
            case .compact: 12
            }
        }

        /// Radius of the orbit each avatar travels along at max count (4).
        var slotRadius: CGFloat {
            switch self {
            case .standard: 23
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
            case .standard: 13
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
            case .standard: 12
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

    /// Each visible avatar slot. `slot` (0–3) drives the per-avatar angular
    /// position within the orbit. `id` is fresh on every swap so SwiftUI's
    /// ForEach fires the transition.
    private struct Avatar: Identifiable {
        let id = UUID()
        let emoji: String
        let slot: Int
    }

    var body: some View {
        Group {
            if reduceMotion || !isAnimating {
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
        // list (e.g. basket changes). Animate so avatar entries/exits and
        // the resulting size shifts feel smooth.
        .onChange(of: emojis) { _, _ in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                initialiseDisplayed()
            }
            startRotation()
        }
    }

    // MARK: - Animated container (full motion)

    private var animatedContainer: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * size.spinSpeed
            ZStack {
                ForEach(displayed) { avatar in
                    avatarView(for: avatar)
                        .offset(slotPosition(for: avatar.slot, spin: phase))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

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
        let d = dynamicAvatarDiameter
        return Text(avatar.emoji)
            .font(.system(size: dynamicEmojiFontSize))
            .frame(width: d, height: d)
            .background {
                Circle().fill(Color("CardBackground"))
            }
            .overlay {
                Circle().strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 0.5)
    }

    // MARK: - Position math

    /// Orbital position of an avatar around the bubble centre.
    ///
    /// Avatars are evenly distributed around the full 360° based on how many
    /// are currently displayed (`displayed.count`), so the cluster always
    /// looks balanced regardless of count:
    ///   1 → centred (slotRadius = 0, no movement)
    ///   2 → top / bottom (180° apart)
    ///   3 → equilateral triangle (120° apart)
    ///   4 → compass points (90° apart)
    ///
    /// `spin` rotates the whole formation so all avatars travel the same
    /// orbit path — relative spacing is preserved, overlap is impossible.
    private func slotPosition(for slot: Int, spin: Double) -> CGSize {
        let count = max(1, displayed.count)
        let restingAngle = (Double(slot) * 2.0 * .pi / Double(count)) - .pi / 2
        let angle = restingAngle + spin
        let r = dynamicSlotRadius
        return CGSize(width: cos(angle) * r, height: sin(angle) * r)
    }

    // MARK: - Dynamic sizing helpers

    /// Avatar circle diameter that scales down as more avatars join the cluster.
    ///
    ///   1 avatar  → large, nearly filling the container
    ///   2 avatars → medium-large
    ///   3 avatars → slightly smaller
    ///   4 avatars → the Size preset's fixed `avatarDiameter`
    private var dynamicAvatarDiameter: CGFloat {
        switch displayed.count {
        case 0, 1: return size == .standard ? 44 : 26
        case 2:    return size == .standard ? 30 : 18
        case 3:    return size == .standard ? 25 : 14
        default:   return size.avatarDiameter
        }
    }

    /// Orbit radius that grows as the cluster fills up.
    ///
    /// At 1 avatar the radius is 0 (avatar sits dead-centre, motionless).
    /// At 4 it matches the Size preset's `slotRadius`.
    private var dynamicSlotRadius: CGFloat {
        switch displayed.count {
        case 0, 1: return 0
        case 2:    return size == .standard ? 16 : 9
        case 3:    return size == .standard ? 20 : 12
        default:   return size.slotRadius
        }
    }

    /// Emoji glyph point size that grows in lock-step with the avatar circle.
    private var dynamicEmojiFontSize: CGFloat {
        switch displayed.count {
        case 0, 1: return size == .standard ? 28 : 16
        case 2:    return size == .standard ? 20 : 11
        case 3:    return size == .standard ? 17 : 9
        default:   return size.emojiFontSize
        }
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
        guard !reduceMotion, emojis.count > slotCount else { return }

        let interval = size.rotationInterval
        rotationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                rotateAvatars()
            }
        }
    }

    /// Each cycle, swap as many slots as we can in parallel — up to
    /// `slotCount - 1` (always keeping at least one stable for visual
    /// continuity). With many extra items the cluster cycles through
    /// the basket much faster than one-at-a-time.
    private func rotateAvatars() {
        let visibleEmojis = Set(displayed.map(\.emoji))
        let hiddenEmojis = emojis.filter { !visibleEmojis.contains($0) }
        guard !hiddenEmojis.isEmpty else { return }

        let maxSwaps = max(1, slotCount - 1)
        let swapCount = min(hiddenEmojis.count, maxSwaps)

        var updated = displayed
        for i in 0..<swapCount {
            let slot = (nextSlotToReplace + i) % slotCount
            guard let index = updated.firstIndex(where: { $0.slot == slot }) else { continue }
            updated[index] = Avatar(emoji: hiddenEmojis[i], slot: slot)
        }

        withAnimation(.easeInOut(duration: 0.7)) {
            displayed = updated
        }

        nextSlotToReplace = (nextSlotToReplace + swapCount) % slotCount
    }
}
