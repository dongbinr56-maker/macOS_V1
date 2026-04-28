import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject var viewModel: UsageMonitorViewModel
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("환경설정")
                            .font(.title3.weight(.semibold))
                        Text("세션 관리, 알림, 자동 실행과 debug 확인을 여기서 관리합니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("닫기") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }

                SettingsActionsView(viewModel: viewModel)

                ForEach(AIPlatform.allCases) { platform in
                    SettingsPlatformSectionView(
                        platform: platform,
                        sessions: viewModel.sessions(for: platform),
                        viewModel: viewModel
                    )
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsActionsView: View {
    @ObservedObject var viewModel: UsageMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("앱 동작")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                SettingsActionButton(
                    title: viewModel.isRefreshingAll ? "갱신 중" : "전체 새로고침",
                    subtitle: "모든 세션 다시 읽기",
                    systemImage: "arrow.clockwise",
                    isProminent: true
                ) {
                    Task {
                        await viewModel.refreshAll()
                    }
                }
                .disabled(viewModel.isRefreshingAll)

                SettingsActionButton(
                    title: "테스트 알림",
                    subtitle: "알림 채널 확인",
                    systemImage: "bell.badge"
                ) {
                    viewModel.sendTestNotification()
                }

                SettingsActionButton(
                    title: "종료",
                    subtitle: "앱 프로세스 종료",
                    systemImage: "power"
                ) {
                    NSApp.terminate(nil)
                }
            }
            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("로그인 시 자동 실행")
                        .font(.subheadline.weight(.medium))
                    Text(viewModel.launchAtLoginManager.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { viewModel.launchAtLoginManager.isEnabled },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                Button("알림 권한 요청") {
                    viewModel.requestNotificationAuthorization()
                }
                .buttonStyle(.bordered)

                Button("시스템 알림 설정") {
                    viewModel.openSystemNotificationSettings()
                }
                .buttonStyle(.bordered)
            }

            if let error = viewModel.launchAtLoginManager.lastErrorDescription, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct SettingsActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isProminent ? Color.white : Color.primary)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isProminent ? Color.white : Color.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isProminent ? Color.white.opacity(0.74) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isProminent ? Color.accentColor.opacity(0.88) : Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke((isProminent ? Color.accentColor : Color.white).opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsPlatformSectionView: View {
    let platform: AIPlatform
    let sessions: [WebAccountSession]
    @ObservedObject var viewModel: UsageMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(platform.displayName) 세션")
                        .font(.headline)
                    Text(sessions.isEmpty ? "연결된 세션이 없습니다." : "독립 세션 \(sessions.count)개 연결됨")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("세션 추가") {
                    viewModel.addAccount(for: platform)
                }
                .buttonStyle(.bordered)
            }

            if sessions.isEmpty {
                Text("새 세션을 추가하면 로그인 창이 열리고, 이후 usage 페이지를 백그라운드에서 다시 읽습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { account in
                    SettingsAccountCardView(account: account, viewModel: viewModel)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

struct SettingsAccountCardView: View {
    let account: WebAccountSession
    @ObservedObject var viewModel: UsageMonitorViewModel

    @State private var draftName: String
    @State private var showingDeleteAlert = false

    init(account: WebAccountSession, viewModel: UsageMonitorViewModel) {
        self.account = account
        self.viewModel = viewModel
        _draftName = State(initialValue: account.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        PlatformBadge(platform: account.platform, compact: true)
                        TextField("계정 이름", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline.weight(.semibold))
                            .onSubmit(saveDisplayName)
                    }

                    Text(account.profileName ?? "프로필 미확인")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await viewModel.refresh(accountID: account.id)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("로그인") {
                    viewModel.reopenLoginWindow(for: account.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if draftName != account.displayName {
                Button("이름 저장", action: saveDisplayName)
                    .buttonStyle(.bordered)
            }

            SessionCardView(
                account: account,
                viewModel: viewModel,
                showsDebugDisclosure: true
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
        .onChange(of: account.displayName) { _, newValue in
            draftName = newValue
        }
        .alert("계정을 삭제할까요?", isPresented: $showingDeleteAlert) {
            Button("삭제", role: .destructive) {
                viewModel.removeAccount(accountID: account.id)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장된 세션과 로컬 데이터스토어를 함께 정리합니다.")
        }
    }

    private func saveDisplayName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = account.displayName
            return
        }

        draftName = trimmed
        viewModel.renameAccount(accountID: account.id, displayName: trimmed)
    }
}

struct PlatformBadge: View {
    let platform: AIPlatform
    var compact = false

    var body: some View {
        Text(platform.shortDisplayName)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 6)
            .background(Capsule(style: .continuous).fill(badgeColor))
    }

    private var badgeColor: Color {
        switch platform {
        case .codex:
            return Color(red: 0.25, green: 0.35, blue: 0.60)
        case .claude:
            return Color(red: 0.63, green: 0.41, blue: 0.18)
        case .cursor:
            return Color(red: 0.16, green: 0.55, blue: 0.42)
        }
    }
}
