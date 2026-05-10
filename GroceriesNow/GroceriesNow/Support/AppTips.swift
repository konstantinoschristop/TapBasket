import TipKit

// MARK: - Add Item Tip

/// Shown above the browse grid on first launch. Teaches the tap-to-add gesture
/// model — non-obvious for newcomers since the grid looks like a static menu.
///
/// The message explicitly mentions all three gestures (tap, long-press, re-tap)
/// because anything less leads users to assume the tile is binary toggle-only.
struct AddItemTip: Tip {
    var title: Text {
        Text("tip.add_item.title")
    }
    var message: Text? {
        Text("tip.add_item.message")
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
        Text("tip.recipe_ai.title")
    }
    var message: Text? {
        Text("tip.recipe_ai.message")
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
        Text("tip.swipe_to_delete.title")
    }
    var message: Text? {
        Text("tip.swipe_to_delete.message")
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
        Text("tip.share_basket.title")
    }
    var message: Text? {
        Text("tip.share_basket.message")
    }
    var image: Image? {
        Image(systemName: "square.and.arrow.up")
    }

    var rules: [Rule] {
        #Rule(Self.$basketItemCount) { $0 >= 2 }
    }
}
