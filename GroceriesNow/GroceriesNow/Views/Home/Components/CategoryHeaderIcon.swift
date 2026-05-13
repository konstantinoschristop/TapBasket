import SwiftUI

/// The 32pt rounded-square icon at the start of every category section
/// header. Uses the project's charcoal AccentColor to stay consistent
/// with the rest of the chrome.
///
/// The icon plays a one-shot `.bounce` when the row first scrolls into
/// view, so as the user scrolls down each section softly announces
/// itself rather than appearing static.
struct CategoryHeaderIcon: View {
    let category: QuickItemCategory

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: category.systemImageName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 32, height: 32)
            .background(
                Color.accentColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .symbolEffect(.bounce, options: .nonRepeating, value: hasAppeared)
            .onAppear {
                guard !reduceMotion else { return }
                // Defer briefly so the row is fully on screen before
                // the bounce fires — otherwise the effect can play
                // before the row finishes animating in and feel detached.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    hasAppeared = true
                }
            }
    }
}
