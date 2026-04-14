import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusDescription = "확인 전"
    @Published private(set) var lastErrorDescription: String?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let service = SMAppService.mainApp

        switch service.status {
        case .enabled:
            isEnabled = true
            statusDescription = "로그인 시 자동 실행"
        case .requiresApproval:
            isEnabled = false
            statusDescription = "시스템 설정에서 승인 필요"
        case .notRegistered:
            isEnabled = false
            statusDescription = "자동 시작 꺼짐"
        case .notFound:
            isEnabled = false
            statusDescription = "앱 번들 환경이 아니어서 등록할 수 없음"
        @unknown default:
            isEnabled = false
            statusDescription = "알 수 없는 상태"
        }
    }

    func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }

            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
        }

        refreshStatus()
    }
}
