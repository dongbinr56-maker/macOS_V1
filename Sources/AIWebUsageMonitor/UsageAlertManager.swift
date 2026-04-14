import AppKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class UsageAlertManager {
    enum AuthorizationState: Equatable {
        case notDetermined
        case denied
        case authorized
        case provisional
        case ephemeral
        case unavailable
    }

    private enum AlertLevel: String {
        case lowQuota
        case exhaustedQuota
        case requiresLogin
        case staleSession
    }

    private let notificationCenter: UNUserNotificationCenter?
    private let accountStore: AccountStore
    private var persistedAlertStates: [String: String]

    init(
        notificationCenter: UNUserNotificationCenter? = nil,
        accountStore: AccountStore
    ) {
        self.notificationCenter = notificationCenter ?? Self.makeNotificationCenter()
        self.accountStore = accountStore
        self.persistedAlertStates = accountStore.loadAlertStates()
    }

    func requestAuthorizationIfNeeded() {
        guard let notificationCenter else {
            return
        }
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                return
            }

            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                // 권한 거부는 앱 동작을 막지 않는다.
            }
        }
    }

    func requestAuthorization(completion: @escaping @Sendable (AuthorizationState) -> Void) {
        guard let notificationCenter else {
            completion(.unavailable)
            return
        }
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        let center = notificationCenter
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            center.getNotificationSettings { settings in
                completion(Self.authorizationState(from: settings.authorizationStatus))
            }
        }
    }

    func fetchAuthorizationStatus(completion: @escaping @Sendable (AuthorizationState) -> Void) {
        guard let notificationCenter else {
            completion(.unavailable)
            return
        }
        notificationCenter.getNotificationSettings { settings in
            completion(Self.authorizationState(from: settings.authorizationStatus))
        }
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }

        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }

    func evaluateAlerts(
        for account: WebAccountSession,
        lowQuotaThreshold: Double,
        idleThreshold: TimeInterval,
        staleThreshold: TimeInterval
    ) {
        if account.refreshState == .requiresLogin {
            let key = alertKey(sessionID: account.id, scope: "auth")
            transitionAlert(
                key: key,
                nextLevel: .requiresLogin,
                title: "\(account.displayName) 로그인 필요",
                body: "\(account.platform.displayName) 세션 로그인이 만료되었거나 확인이 필요합니다.",
                subtitle: nil
            )
        } else {
            clearAlert(key: alertKey(sessionID: account.id, scope: "auth"))
        }

        if account.activityState(idleThreshold: idleThreshold, staleThreshold: staleThreshold) == .stale {
            let key = alertKey(sessionID: account.id, scope: "stale")
            transitionAlert(
                key: key,
                nextLevel: .staleSession,
                title: "\(account.displayName) 세션 갱신 지연",
                body: "최근 성공적인 상태 갱신이 오래되어 세션 상태를 신뢰하기 어렵습니다.",
                subtitle: nil
            )
        } else {
            clearAlert(key: alertKey(sessionID: account.id, scope: "stale"))
        }

        guard let snapshot = account.snapshot else {
            clearQuotaAlerts(for: account.id)
            return
        }

        let primaryEntries = snapshot.primaryQuotaEntries(for: account.platform)
        let activeQuotaKeys = Set(primaryEntries.map { alertKey(sessionID: account.id, scope: "quota-\($0.label)") })
        clearQuotaAlerts(for: account.id, excluding: activeQuotaKeys)

        for entry in primaryEntries {
            let key = alertKey(sessionID: account.id, scope: "quota-\(entry.label)")
            guard let remainingRatio = entry.progress ?? extractQuotaPercent(from: entry.valueText) else {
                clearAlert(key: key)
                continue
            }

            if remainingRatio <= 0 {
                transitionAlert(
                    key: key,
                    nextLevel: .exhaustedQuota,
                    title: "\(account.displayName) 사용 불가",
                    body: "\(entry.label)이 소진되어 현재 \(account.platform.displayName)를 사용할 수 없습니다.",
                    subtitle: entry.resetText
                )
            } else if remainingRatio <= lowQuotaThreshold {
                transitionAlert(
                    key: key,
                    nextLevel: .lowQuota,
                    title: "\(account.displayName) 한도 경고",
                    body: "\(entry.label)이 \(Int((remainingRatio * 100).rounded()))% 남았습니다.",
                    subtitle: entry.resetText
                )
            } else {
                clearAlert(key: key)
            }
        }
    }

    func sendTestNotification() {
        guard let notificationCenter else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "AI Web Ops Monitor 테스트"
        content.body = "알림 채널이 정상적으로 동작하는지 확인하는 테스트 알림입니다."
        content.subtitle = "앱에서 직접 발송됨"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "quota-warning-test",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { _ in
            // 테스트 알림 실패는 앱 동작을 막지 않는다.
        }
    }

    private func transitionAlert(
        key: String,
        nextLevel: AlertLevel,
        title: String,
        body: String,
        subtitle: String?
    ) {
        guard let notificationCenter else {
            return
        }
        if persistedAlertStates[key] == nextLevel.rawValue {
            return
        }

        persistedAlertStates[key] = nextLevel.rawValue
        accountStore.saveAlertState(key: key, level: nextLevel.rawValue)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: key,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { _ in
            // 알림 실패는 앱 동작을 막지 않는다.
        }
    }

    private func clearAlert(key: String) {
        guard persistedAlertStates[key] != nil else {
            return
        }

        persistedAlertStates.removeValue(forKey: key)
        accountStore.removeAlertState(key: key)
    }

    private func alertKey(sessionID: UUID, scope: String) -> String {
        "alert::\(sessionID.uuidString)::\(scope)"
    }

    private func clearQuotaAlerts(for sessionID: UUID, excluding activeKeys: Set<String> = []) {
        let prefix = "alert::\(sessionID.uuidString)::quota-"
        let staleKeys = persistedAlertStates.keys.filter { key in
            key.hasPrefix(prefix) && !activeKeys.contains(key)
        }

        for key in staleKeys {
            clearAlert(key: key)
        }
    }

    nonisolated private static func authorizationState(from status: UNAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .notDetermined
        }
    }

    nonisolated private static func makeNotificationCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        return .current()
    }
}
