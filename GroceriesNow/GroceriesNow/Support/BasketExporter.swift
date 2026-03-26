import SwiftUI

// MARK: - Sendable snapshot models (safe to pass across concurrency boundaries)

struct BasketItemSnapshot: Sendable {
    let name: String
    let emoji: String
    let quantity: Int
    let note: String?
}

struct RecipeGroupSnapshot: Sendable {
    let name: String
    let items: [BasketItemSnapshot]
}

// MARK: - Renderer

@MainActor
enum BasketExporter {
    /// Returns a fully composited, opaque UIImage ready to hand to UIActivityViewController.
    static func renderImage(
        regularItems: [BasketItemSnapshot],
        recipeGroups: [RecipeGroupSnapshot]
    ) -> UIImage? {
        let view = BasketShareView(regularItems: regularItems, recipeGroups: recipeGroups)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .init(width: 390, height: nil) // phone width, natural height
        renderer.scale = 3 // @3x — sharp on all devices and when saved to Photos

        guard let rendered = renderer.uiImage else { return nil }

        // ImageRenderer always produces an alpha-channel image even for opaque content.
        // Composite onto a white opaque canvas to eliminate the alpha channel.
        // Preserve rendered.scale (3×) so the output pixel dimensions stay full-res.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = rendered.scale
        let opaqueRenderer = UIGraphicsImageRenderer(size: rendered.size, format: format)
        return opaqueRenderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: rendered.size))
            rendered.draw(at: .zero)
        }
    }
}
