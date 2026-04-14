import AppKit
import SwiftUI

@main
struct AIWebUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsPlaceholderView()
        }
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Web Ops Monitor")
                .font(.title3.weight(.semibold))
            Text("이 앱은 Dock이 아닌 메뉴바에서 동작합니다. 상단바 아이콘을 클릭해 Codex, Claude, Cursor 세션을 연결하고 상태를 확인하세요.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var viewModel: UsageMonitorViewModel?
    private var alertManager: UsageAlertManager?
    private var accountStore: AccountStore?
    private var debugWindowController: DebugWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shouldPresentDebugWindow = CommandLine.arguments.contains("--debug-window")
        NSApp.setActivationPolicy(shouldPresentDebugWindow ? .regular : .accessory)

        let accountStore = AccountStore()
        let alertManager = UsageAlertManager(accountStore: accountStore)
        let viewModel = UsageMonitorViewModel(
            sessionManager: WebSessionManager(),
            accountStore: accountStore,
            alertManager: alertManager,
            launchAtLoginManager: LaunchAtLoginManager(),
            refreshInterval: 60,
            lowQuotaThreshold: 0.20,
            idleThreshold: 10 * 60,
            staleThreshold: 15 * 60,
            refreshConcurrencyLimit: 2
        )
        let statusBarController = StatusBarController(viewModel: viewModel)

        self.accountStore = accountStore
        self.alertManager = alertManager
        self.viewModel = viewModel
        self.statusBarController = statusBarController

        alertManager.requestAuthorizationIfNeeded()
        viewModel.start()

        if shouldPresentDebugWindow {
            let debugWindowController = DebugWindowController(viewModel: viewModel)
            debugWindowController.present()
            self.debugWindowController = debugWindowController
        }

        if CommandLine.arguments.contains("--test-notification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                alertManager.sendTestNotification()
            }
        }
    }
}

@MainActor
final class DebugWindowController: NSWindowController, NSWindowDelegate {
    init(viewModel: UsageMonitorViewModel) {
        let rootView = MenuBarPopoverView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: MenuBarPopoverView.popoverSize.width,
                height: MenuBarPopoverView.popoverSize.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Web Ops Monitor Debug"
        window.contentViewController = hostingController
        window.setContentSize(
            NSSize(
                width: MenuBarPopoverView.popoverSize.width,
                height: MenuBarPopoverView.popoverSize.height
            )
        )
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if NSApp.activationPolicy() == .regular {
            NSApp.terminate(nil)
        }
    }
}
