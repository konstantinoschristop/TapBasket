import UIKit

protocol BasketHapticProviding {
    func itemAdded()
    func basketCompleted()
}

struct BasketHaptics: BasketHapticProviding {
    func itemAdded() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    func basketCompleted() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}