import SwiftUI

/// A ButtonStyle that applies a spring scale on press for immediate tactile feedback.
struct SpringButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SpringButtonStyle {
    static var spring: SpringButtonStyle { .init() }
    static func spring(scale: CGFloat) -> SpringButtonStyle { .init(scale: scale) }
}
