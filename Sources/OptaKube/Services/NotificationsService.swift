import Foundation
import UserNotifications
import AppKit

/// Watches pod restart counts across refresh ticks and fires a system notification
/// when one increases. State is kept in-memory only — restarts that happen while
/// OptaKube is closed don't notify (no persistent baseline). Gated by the
/// `notifyPodRestarts` user default.
@MainActor
final class NotificationsService {
    static let shared = NotificationsService()

    /// `(clusterId, namespace/podName)` → last seen total restart count.
    private var lastSeen: [String: [String: Int]] = [:]

    private var authorizationRequested = false

    func observe(pods: [Pod], clusterId: String) {
        guard UserDefaults.standard.object(forKey: "notifyPodRestarts") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "notifyPodRestarts") else { return }

        ensureAuthorization()

        var clusterMap = lastSeen[clusterId] ?? [:]
        var firedAny = false
        for pod in pods {
            let key = "\(pod.metadata.namespace ?? "")/\(pod.name)"
            let count = pod.restartCount
            if let prev = clusterMap[key], count > prev {
                let delta = count - prev
                let ns = pod.metadata.namespace ?? "default"
                fire(
                    title: "Pod restart",
                    body: "\(pod.name) in \(ns) restarted (\(delta == 1 ? "+1, now" : "now") \(count))",
                    threadId: "pod-restart.\(clusterId).\(key)"
                )
                firedAny = true
            }
            clusterMap[key] = count
        }
        lastSeen[clusterId] = clusterMap
        if firedAny {
            // Tickle the dock badge so a user not looking at the menu bar also notices.
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    /// Reset the baseline for a cluster, e.g. when (dis)connecting or switching
    /// kubeconfigs, so we don't fire spurious notifications against stale numbers.
    func reset(clusterId: String) {
        lastSeen.removeValue(forKey: clusterId)
    }

    private func ensureAuthorization() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func fire(title: String, body: String, threadId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = threadId
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
