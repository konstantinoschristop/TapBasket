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
    var undoLabel: String?
    var onUndo: (() -> Void)?

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

    private let diameter: CGFloat = 78
    private let edgePadding: CGFloat = 16
    /// Bottom clearance: accounts for the home indicator on modern iPhones.
    private let bottomClearance: CGFloat = 52

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            faceWithTransitionSource
                .scaleEffect(scale)
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
                .contextMenu {
                    if let label = undoLabel, let action = onUndo {
                        Button(role: .destructive, action: action) {
                            Label(label, systemImage: "arrow.uturn.backward")
                        }
                    }
                }
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
        .opacity(count > 0 ? 1 : 0)
        .scaleEffect(count > 0 ? 1 : 0.7)
        .animation(.taplistTransition, value: count > 0)
        .allowsHitTesting(count > 0)
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

    /// Applies the zoom transition source on iOS 18+; plain face on earlier OS.
    @ViewBuilder
    private var faceWithTransitionSource: some View {
        if #available(iOS 18.0, *) {
            face.matchedTransitionSource(id: "basket", in: namespace)
        } else {
            face
        }
    }

    @ViewBuilder
    private var face: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                // Solid base — always visible over any list content
                Circle()
                    .fill(Color("CardBackground"))

                // Specular highlight: fades from white at top to clear at centre,
                // giving the button a gently convex, pressable quality.
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.20), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                BasketItemBubbles(emojis: emojis, size: .standard, isAnimating: !isFrozen)
            }
            .frame(width: diameter, height: diameter)
            // Gradient rim: bright at top (catches the light), subtle at bottom
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color(.separator).opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
            // Cast shadow — tight and sharp, anchors the button to the surface
            .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 4)
            // Ambient shadow — wide and soft, creates the "floating above" depth
            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
            .contentShape(Circle())

            // Item count badge — top-right corner
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    // White ring separates the badge from the button surface
                    .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 1.5)
                    .offset(x: 6, y: -6)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
