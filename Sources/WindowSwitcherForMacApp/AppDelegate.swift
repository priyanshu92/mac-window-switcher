import AppCore
import AppKit
import PlatformServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = UserDefaultsSwitcherSettingsStore()
    private let permissionsService = MacPermissionsService()
    private let windowService = MacWindowService()
    private let commandTabMonitor = CommandTabMonitor()

    private var switcherController: SwitcherController!
    private var statusItemController: StatusItemController!
    private var preferencesController: PreferencesWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDevelopmentIcon()

        switcherController = SwitcherController(
            windowService: windowService,
            settingsStore: settingsStore
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

        startMonitorIfEnabled()

        let permissions = permissionsService.snapshot()
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            DispatchQueue.main.async { [weak self] in
                self?.switcherController.showForMenu()
            }
        } else if !permissions.canRunSwitcher || permissions.screenRecording != .granted {
            preferencesController.showWindow(nil)
            preferencesController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        preferencesController?.refresh()
        statusItemController?.refresh()
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
