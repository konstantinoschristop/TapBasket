import SwiftUI

extension View {
    /// Applies native Liquid Glass on iOS 26+; falls back to `.ultraThinMaterial` on older OS.
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        modifier(AdaptiveGlassModifier(shape: shape))
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
