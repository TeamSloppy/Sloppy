import Foundation

private final class NotificationObserverToken: @unchecked Sendable {
    let center: NotificationCenter
    let observer: any NSObjectProtocol

    init(center: NotificationCenter, observer: any NSObjectProtocol) {
        self.center = center
        self.observer = observer
    }

    func remove() {
        center.removeObserver(observer)
    }
}

struct SloppyNotification: @unchecked Sendable {
    let rawValue: Notification
}

extension NotificationCenter {
    func sloppyNotifications(named name: Notification.Name) -> AsyncStream<SloppyNotification> {
        AsyncStream { continuation in
            let observer = addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { notification in
                continuation.yield(SloppyNotification(rawValue: notification))
            }
            let token = NotificationObserverToken(center: self, observer: observer)

            continuation.onTermination = { _ in
                token.remove()
            }
        }
    }
}
