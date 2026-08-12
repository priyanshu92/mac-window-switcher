import AppCore
import AppKit
import PlatformServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = UserDefaultsSwitcherSettingsStore()
    private let permissionsService = MacPermissionsService()
    private let windowService = MacWindowService()
    private let commandTabMonitor = CommandTabMonitor()
    private let dockInteractionMonitor = DockInteractionMonitor()

    private var switcherController: SwitcherController!
    private var statusItemController: StatusItemController!
    private var preferencesController: PreferencesWindowController!
    private var dockHoverTask: Task<Void, Never>?
    private var dockDismissTask: Task<Void, Never>?
    private var hoveredDockProcessIdentifier: pid_t?
    private var pendingDockHoverProcessIdentifier: pid_t?
    private var suppressDockHoverUntil = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDevelopmentIcon()

        switcherController = SwitcherController(
            windowService: windowService,
            settingsStore: settingsStore
        )
        switcherController.startActivityTracking()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceApplicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        statusItemController = StatusItemController(
            settingsStore: settingsStore,
            permissionsService: permissionsService,
            delegate: self
        )
        preferencesController = PreferencesWindowController(
            settingsStore: settingsStore,
            permissionsService: permissionsService,
            delegate: self
        )

        commandTabMonitor.handler = { [weak self] gesture in
            DispatchQueue.main.async {
                guard let self, self.settingsStore.load().isEnabled else { return }
                self.switcherController.handle(gesture)
            }
        }
        dockInteractionMonitor.handler = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleDockInteraction(event)
            }
        }

        startMonitorIfEnabled()
        startDockMonitorIfEnabled()

        let permissions = permissionsService.snapshot()
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            DispatchQueue.main.async { [weak self] in
                self?.switcherController.showForMenu()
            }
        } else if
            ProcessInfo.processInfo.arguments.contains("--preferences")
                || !permissions.canRunSwitcher
                || permissions.screenRecording != .granted
        {
            preferencesController.showWindow(nil)
            preferencesController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        preferencesController?.refresh()
        statusItemController?.refresh()
    }

    @objc
    private func workspaceApplicationDidActivate(_ notification: Notification) {
        switcherController.observeActiveWindow()
    }

    private func startMonitorIfEnabled() {
        guard settingsStore.load().isEnabled else {
            commandTabMonitor.stop()
            return
        }

        do {
            try commandTabMonitor.start()
        } catch {
            switcherLog(error.localizedDescription)
            presentError(error)
        }
    }

    private func startDockMonitorIfEnabled() {
        guard settingsStore.load().dockWindowPreviewsEnabled else {
            dockInteractionMonitor.stop()
            cancelDockHover()
            switcherController.dismissDockPreview()
            return
        }

        do {
            try dockInteractionMonitor.start()
        } catch {
            switcherLog(error.localizedDescription)
            presentError(error)
        }
    }

    private func handleDockInteraction(_ event: DockInteractionEvent) {
        guard settingsStore.load().dockWindowPreviewsEnabled else { return }

        switch event {
        case let .hover(target):
            handleDockHover(target)
        case let .click(target):
            handleDockClick(target)
        case .contextMenu:
            cancelDockHover()
            dockInteractionMonitor.suppressHoverUntilPointerLeavesDock()
            switcherController.dismissDockPreview()
        }
    }

    private func handleDockHover(_ target: DockApplicationTarget?) {
        guard Date() >= suppressDockHoverUntil else { return }

        guard
            let target,
            let application = runningApplication(for: target)
        else {
            hoveredDockProcessIdentifier = nil
            cancelPendingDockHover()
            scheduleDockDismissal()
            return
        }

        let processIdentifier = application.processIdentifier
        hoveredDockProcessIdentifier = processIdentifier
        dockDismissTask?.cancel()
        dockDismissTask = nil

        if switcherController.isShowingDockWindows(processIdentifier: processIdentifier) {
            cancelPendingDockHover()
            return
        }
        guard pendingDockHoverProcessIdentifier != processIdentifier else { return }

        cancelPendingDockHover()
        pendingDockHoverProcessIdentifier = processIdentifier
        dockHoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(DockPreviewTiming.hoverIntentDelay * 1_000_000_000)
            )
            guard
                !Task.isCancelled,
                let self,
                self.hoveredDockProcessIdentifier == processIdentifier
            else {
                return
            }
            self.pendingDockHoverProcessIdentifier = nil
            self.dockHoverTask = nil
            _ = self.switcherController.showDockWindows(processIdentifier: processIdentifier)
        }
    }

    private func handleDockClick(_ target: DockApplicationTarget) {
        suppressDockHoverUntil = Date().addingTimeInterval(0.7)
        hoveredDockProcessIdentifier = nil
        cancelDockHover()

        guard let application = runningApplication(for: target) else {
            reopenApplication(at: target.bundleURL)
            return
        }

        switch switcherController.handleDockClick(
            processIdentifier: application.processIdentifier
        ) {
        case .noWindows:
            reopenApplication(at: target.bundleURL)
        case .activatedWindow, .presentedWindows:
            break
        }
    }

    private func scheduleDockDismissal() {
        guard dockDismissTask == nil else { return }

        dockDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self else { return }
            self.dockDismissTask = nil
            if !self.switcherController.isPointerInsideDockPanel() {
                self.switcherController.dismissDockPreview()
            }
        }
    }

    private func cancelPendingDockHover() {
        dockHoverTask?.cancel()
        dockHoverTask = nil
        pendingDockHoverProcessIdentifier = nil
    }

    private func cancelDockHover() {
        cancelPendingDockHover()
        dockDismissTask?.cancel()
        dockDismissTask = nil
        hoveredDockProcessIdentifier = nil
    }

    private func runningApplication(
        for target: DockApplicationTarget
    ) -> NSRunningApplication? {
        let targetURL = target.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == targetURL
        }
    }

    private func reopenApplication(at bundleURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration
        ) { _, error in
            if let error {
                switcherLog("Opening Dock application failed: \(error.localizedDescription)")
            }
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func refreshPermissionUI() {
        preferencesController.refresh()
        statusItemController.refresh()
    }

    private func applyDevelopmentIcon() {
        let iconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIcon.png")
        if let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }
}

extension AppDelegate: StatusItemControllerDelegate {
    func showSwitcher() {
        switcherController.showForMenu()
    }

    func showPreferences() {
        preferencesController.showWindow(nil)
        preferencesController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setSwitcherEnabled(_ enabled: Bool) {
        var settings = settingsStore.load()
        settings.isEnabled = enabled
        do {
            try settingsStore.save(settings)
            startMonitorIfEnabled()
            preferencesController.refresh()
            statusItemController.refresh()
        } catch {
            presentError(error)
        }
    }

    func requestAccessibility() {
        _ = permissionsService.requestAccessibility()
        refreshPermissionUI()
    }

    func requestScreenRecording() {
        _ = permissionsService.requestScreenRecording()
        refreshPermissionUI()
    }

    func openInputMonitoringSettings() {
        _ = permissionsService.openInputMonitoringSettings()
        refreshPermissionUI()
    }

    func quitApplication() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: PreferencesWindowControllerDelegate {
    func preferencesDidChange(_ settings: SwitcherSettings) {
        startMonitorIfEnabled()
        startDockMonitorIfEnabled()
        statusItemController.refresh()
    }

    func preferencesDidRequestPreview() {
        switcherController.showForMenu()
    }

    func preferencesDidRequestAccessibility() {
        requestAccessibility()
    }

    func preferencesDidRequestScreenRecording() {
        requestScreenRecording()
    }

    func preferencesDidRequestInputMonitoring() {
        openInputMonitoringSettings()
    }
}
