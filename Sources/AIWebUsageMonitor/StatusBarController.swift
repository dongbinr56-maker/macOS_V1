import AppKit
import Combine
import SwiftUI

private enum MenuBarDisplayMode: String {
    case office
    case list
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var eventMonitor: PopoverEventMonitor?
    private let viewModel: UsageMonitorViewModel
    private var cancellables = Set<AnyCancellable>()
    private let displayModeDefaultsKey = "menuBarDisplayMode"

    init(viewModel: UsageMonitorViewModel) {
        self.viewModel = viewModel
        super.init()
        configurePopover()
        configureStatusItem()
        configureEventMonitor()
        bindViewModel()
        updateStatusItemAppearance()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(
            width: MenuBarPopoverView.popoverSize.width,
            height: MenuBarPopoverView.popoverSize.height
        )
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(viewModel: viewModel)
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func bindViewModel() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
    }

    private func configureEventMonitor() {
        eventMonitor = PopoverEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] in
            self?.hidePopover(nil)
        }
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        if popover.isShown {
            hidePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor?.start()
    }

    private func hidePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }

    private func showStatusMenu() {
        hidePopover(nil)
        statusItem.menu = makeStatusMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let officeItem = NSMenuItem(
            title: "픽셀 오피스 열기",
            action: #selector(openOfficeMode),
            keyEquivalent: ""
        )
        officeItem.target = self
        officeItem.state = currentDisplayMode == .office ? .on : .off
        menu.addItem(officeItem)

        let listItem = NSMenuItem(
            title: "리스트 보기",
            action: #selector(openListMode),
            keyEquivalent: ""
        )
        listItem.target = self
        listItem.state = currentDisplayMode == .list ? .on : .off
        menu.addItem(listItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: viewModel.isRefreshingAll ? "새로고침 중" : "전체 새로고침",
            action: #selector(refreshAllSessions),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = !viewModel.isRefreshingAll
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc
    private func openOfficeMode() {
        setDisplayMode(.office)
        showPopover(nil)
    }

    @objc
    private func openListMode() {
        setDisplayMode(.list)
        showPopover(nil)
    }

    @objc
    private func refreshAllSessions() {
        Task {
            await viewModel.refreshAll()
        }
    }

    @objc
    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else {
            return
        }

        let summary = viewModel.overallStatusSummary
        let image = NSImage(
            systemSymbolName: summary.symbolName,
            accessibilityDescription: summary.accessibilityLabel
        )

        image?.isTemplate = true
        button.image = image
        button.title = image == nil ? "GPT" : ""
        button.toolTip = summary.subtitle
        button.setAccessibilityLabel(summary.accessibilityLabel)
    }

    private var currentDisplayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: displayModeDefaultsKey) ?? MenuBarDisplayMode.office.rawValue
        ) ?? .office
    }

    private func setDisplayMode(_ mode: MenuBarDisplayMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: displayModeDefaultsKey)
    }
}

private final class PopoverEventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: () -> Void
    private var monitor: Any?

    init(mask: NSEvent.EventTypeMask, handler: @escaping () -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handler()
        }
    }

    func stop() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
