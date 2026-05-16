import SwiftUI

/// Compact, repositionable basket access button.
///
/// A glass circle containing the animated emoji cluster floats freely over the
/// home screen. Drag it to any position — on release it snaps to the nearest
/// horizontal edge with a spring animation. Position persists across launches.
///
/// - Tap: opens the basket sheet.
/// - Long-press: shows an Undo context menu when a recent add is available.
/// - Drag (≥ 8 pt): repositions the button; snaps to nearest edge on release.
struct FloatingBasketButton: View {

    let emojis: [String]
    let count: Int
    /// External scale factor — driven by the add-pulse animation in the parent.
    var scale: CGFloat = 1
    /// Shared namespace for the zoom navigation transition.
    var namespace: Namespace.ID
    var onTap: () -> Void

    // MARK: - Position state

    /// Live position driven directly during drag, then animated into the snapped target.
    /// Using @State (not @GestureState) means there is no instant reset on gesture end —
    /// the button springs smoothly from wherever the finger left it.
    @State private var position: CGPoint = .zero
    /// Captured at the moment a drag begins so subsequent translations are relative to it.
    @State private var dragStart: CGPoint = .zero
    @State private var isDragging = false
    /// Guards against re-seeding `position` on every re-render after first placement.
    @State private var placed = false
    /// Frozen while the zoom transition plays so TimelineView stops invalidating
    /// the source view, giving the transition renderer a clean, stable snapshot.
    @State private var isFrozen = false

    /// Whether the button is pinned to the right edge (true) or left (false).
    @AppStorage("floatingBasket.snapRight") private var snapRight: Bool = true
    /// Vertical position as a fraction (0 = top of range, 1 = bottom).
    @AppStorage("floatingBasket.yFraction") private var yFraction: Double = 0.78

    /// 80pt is roughly −10% from the prior 88pt — the bubble still
    /// reads as a hero affordance but stops competing with content
    /// while you scan the grid. Edge padding stays the same so the
    /// resting position visually anchors at the same offset.
    private let diameter: CGFloat = 80
    private let edgePadding: CGFloat = 16
    /// Bottom clearance: accounts for the home indicator on modern iPhones.
    private let bottomClearance: CGFloat = 52

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            face
                .scaleEffect(scale * (isDragging ? 1.04 : 1))
                // Idle opacity sits below 1 so the button feels ambient
                // while the user is scanning the grid. Drag wakes it
                // fully — the basket is "alive when needed".
                .opacity(count > 0 ? (isDragging ? 1.0 : 0.92) : 0)
                .position(position)
                .gesture(dragGesture(in: geo.size))
                .onTapGesture {
                    // Freeze the spin before handing off to the transition so the
                    // TimelineView stops firing on every frame during the animation.
                    isFrozen = true
                    onTap()
                    Task {
                        // Zoom transition typically completes in ~0.5 s; wait a bit
                        // past that so the resume doesn't interrupt the tail of the arc.
                        try? await Task.sleep(for: .milliseconds(700))
                        await MainActor.run { isFrozen = false }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isDragging)
                .onAppear {
                    guard !placed else { return }
                    position = anchorPoint(in: geo.size)
                    placed = true
                }
                .onChange(of: geo.size) { _, newSize in
                    // Re-anchor when orientation changes.
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        position = anchorPoint(in: newSize)
                    }
                }
        }
        .scaleEffect(count > 0 ? 1 : 0.7)
        .animation(.taplistTransition, value: count > 0)
        .allowsHitTesting(count > 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            String(localized: "basket.button.a11y_format",
                   defaultValue: "Basket, \(count) items",
                   comment: "VoiceOver label for the floating basket button. %lld is the item count.")
        ))
        .accessibilityHint(Text("basket.button.a11y_hint"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Drag gesture

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStart = position
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                // Follow the finger directly — no animation, no lag.
                position = CGPoint(
                    x: dragStart.x + value.translation.width,
                    y: dragStart.y + value.translation.height
                )
            }
            .onEnded { _ in
                isDragging = false

                let minY   = diameter / 2 + 8
                let maxY   = size.height - diameter / 2 - bottomClearance
                let clampY = min(max(position.y, minY), maxY)
                let goRight = position.x >= size.width / 2
                let snapX  = goRight
                    ? size.width  - edgePadding - diameter / 2
                    : edgePadding + diameter / 2

                // Animate from the exact drop point into the snapped target.
                withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                    position = CGPoint(x: snapX, y: clampY)
                }

                // Persist for next launch.
                snapRight = goRight
                yFraction = Double((clampY - minY) / max(maxY - minY, 1))

                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
    }

    // MARK: - Layout

    private func anchorPoint(in size: CGSize) -> CGPoint {
        let minY = diameter / 2 + 8
        let maxY = size.height - diameter / 2 - bottomClearance
        let y = minY + CGFloat(yFraction) * max(maxY - minY, 0)
        let x = snapRight
            ? size.width - edgePadding - diameter / 2
            : edgePadding + diameter / 2
        return CGPoint(x: x, y: y)
    }

    // MARK: - Visuals

    /// The full face = circular button surface + count badge.
    ///
    /// The badge is in an overlay *outside* the transition source — otherwise
    /// iOS 18's `matchedTransitionSource` wraps the entire view in its
    /// implicit transition container (rounded-rect bounds), which clips the
    /// offset badge and leaves a faint corner outline visible on the source.
    @ViewBuilder
    private var face: some View {
        buttonSurface
            .overlay(alignment: .topTrailing) {
                countBadge
                    .offset(x: 6, y: -6)
            }
    }

    /// The circular button surface — this alone is the zoom transition source.
    ///
    /// Background uses the project's `adaptiveGlass` modifier: native iOS 26
    /// `glassEffect` where available, `.ultraThinMaterial` on older OS. The
    /// gradient highlight + defined rim sit on top of that glass for
    /// dimensional cues and clear separation from content behind.
    @ViewBuilder
    private var buttonSurface: some View {
        let surface = ZStack {
            // Specular highlight at the top — adds a hint of convexity over
            // the otherwise flat glass material.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            BasketItemBubbles(emojis: emojis, size: .standard, isAnimating: !isFrozen)
        }
        .frame(width: diameter, height: diameter)
        // Glass background — the visual replacement for the solid CardBackground fill.
        .adaptiveGlass(in: Circle())
        // Defined rim — does the work the drop shadow used to: separating the
        // button from whatever it's floating over. Softened from a 1.5pt
        // gradient stroke to a quieter 1pt rim so the button reads as
        // ambient glass rather than a chrome-edged badge.
        .overlay {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color(.separator).opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .contentShape(Circle())

        if #available(iOS 18.0, *) {
            surface.matchedTransitionSource(id: "basket", in: namespace)
        } else {
            surface
        }
    }

    @ViewBuilder
    private var countBadge: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color(uiColor: .systemBackground))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                .contentTransition(.numericText(value: Double(count)))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
