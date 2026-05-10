import UIKit

protocol BasketHapticProviding {
    func itemAdded()
    func itemRemoved()
    func basketCompleted()
}

struct BasketHaptics: BasketHapticProviding {
    func itemAdded() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    func itemRemoved() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
    }

    func basketCompleted() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}