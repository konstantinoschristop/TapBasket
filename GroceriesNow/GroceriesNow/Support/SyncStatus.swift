import Foundation
import CoreData
import Observation

/// Lightweight wrapper around `NSPersistentCloudKitContainer`'s event
/// stream. SwiftData uses an `NSPersistentCloudKitContainer` under
/// the hood, so the same notifications still fire when the CloudKit
/// mirroring layer pulls records down or pushes them up. We capture
/// the most recent successful timestamp so the UI can show a quiet
/// "last synced" caption without the user wondering whether iCloud is
/// actually doing anything.
///
/// Threading: the type is `@MainActor` so the observed property is
/// safe to read from SwiftUI bodies. The notification callback bounces
/// onto the main actor via `Task { @MainActor ... }` to satisfy
/// strict-concurrency without depending on the dispatch queue we
/// register with.
///
/// Lifetime: registered once via the shared singleton and lives for
/// the app's lifetime — no need to tear down on deinit. Touch the
/// singleton *before* `ModelContainer` initialisation so early setup
/// events aren't missed.
@MainActor
@Observable
final class SyncStatus {
    static let shared = SyncStatus()

    /// Timestamp of the most recent successful CloudKit import or
    /// export. `nil` until the first one completes; UI hides the
    /// caption while this is `nil` so the empty state doesn't read
    /// as a sync failure on a fresh install.
    private(set) var lastSyncedAt: Date?

    /// Hold the observer token so the subscription outlives `init`.
    /// Marked `nonisolated(unsafe)` because `NotificationCenter`
    /// returns an `Any` token that's safe to retain across actors —
    /// we never mutate it after `init`.
    private nonisolated(unsafe) var observerToken: NSObjectProtocol?

    private init() {
        observerToken = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard
                let userInfo = notification.userInfo,
                let event = userInfo[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                event.succeeded
            else { return }

            // `.setup` fires once on container init and doesn't
            // represent ongoing data movement — skip so the caption
            // only reflects real sync activity.
            switch event.type {
            case .import, .export:
                guard let endDate = event.endDate else { return }
                Task { @MainActor [weak self] in
                    self?.lastSyncedAt = endDate
                }
            default:
                break
            }
        }
    }
}
