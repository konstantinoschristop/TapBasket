import SwiftUI

extension View {
    /// Applies native Liquid Glass on iOS 26+; falls back to `.ultraThinMaterial` on older OS.
    /// Best for floating cards/containers where the frosted blur reads well.
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        modifier(AdaptiveGlassModifier(shape: shape))
    }

    /// Applies native Liquid Glass on iOS 26+; falls back to a translucent white tint on older OS.
    /// Use for tiles on a coloured background where ultraThinMaterial would look opaque/white.
    func tileGlass<S: Shape>(in shape: S) -> some View {
        modifier(TileGlassModifier(shape: shape))
    }
}

private struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color(.separator).opacity(0.15), lineWidth: 0.5))
        }
    }
}

private struct TileGlassModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(.white.opacity(0.45)))
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.9), .white.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        }
    }
}
