import TipKit

// MARK: - Add Item Tip

/// Shown above the browse grid on first launch.
struct AddItemTip: Tip {
    var title: Text {
        Text("Tap to add to basket")
    }
    var message: Text? {
        Text("Tap any item once to add it. Tap again to increase the quantity.")
    }
    var image: Image? {
        Image(systemName: "hand.tap.fill")
    }
}

// MARK: - Recipe AI Tip

/// Shown as a popover on the sparkles toolbar button (iOS 26+ only).
/// No parameter rules needed — the button itself is only visible when AI is available.
struct RecipeAITip: Tip {
    var title: Text {
        Text("AI Shopping Lists")
    }
    var message: Text? {
        Text("Type any recipe and Taplist builds your shopping list automatically.")
    }
    var image: Image? {
        Image(systemName: "sparkles")
    }
}

// MARK: - Swipe to Delete Tip

/// Shown at the top of the basket once at least one item exists.
struct SwipeToDeleteTip: Tip {
    @Parameter static var basketItemCount: Int = 0

    var title: Text {
        Text("Swipe to remove")
    }
    var message: Text? {
        Text("Swipe left on any basket item to remove it.")
    }
    var image: Image? {
        Image(systemName: "trash")
    }

    var rules: [Rule] {
        #Rule(Self.$basketItemCount) { $0 >= 1 }
    }
}

// MARK: - Share Basket Tip

/// Shown as a popover on the share button once the basket has 2+ items.
struct ShareBasketTip: Tip {
    @Parameter static var basketItemCount: Int = 0

    var title: Text {
        Text("Share your list")
    }
    var message: Text? {
        Text("Export your basket as an image to share with friends and family.")
    }
    var image: Image? {
        Image(systemName: "square.and.arrow.up")
    }

    var rules: [Rule] {
        #Rule(Self.$basketItemCount) { $0 >= 2 }
    }
}
