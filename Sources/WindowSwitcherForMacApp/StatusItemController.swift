import AppCore
import AppKit
import PlatformServices
import ServiceManagement

@MainActor
protocol StatusItemControllerDelegate: AnyObject {
    func showSwitcher()
    func showPreferences()
    func setSwitcherEnabled(_ enabled: Bool)
    func requestAccessibility()
    func requestScreenRecording()
    func openInputMonitoringSettings()
    func quitApplication()
}

@MainActor
final class StatusItemController: NSObject {
    private let settingsStore: SwitcherSettingsStore
    private let permissionsService: PermissionsService
    private weak var delegate: StatusItemControllerDelegate?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(
        settingsStore: SwitcherSettingsStore,
        permissionsService: PermissionsService,
        delegate: StatusItemControllerDelegate
    ) {
        self.settingsStore = settingsStore
        self.permissionsService = permissionsService
        self.delegate = delegate
        super.init()

        let image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "Window Switcher"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "Window Switcher"
        refresh()
    }

    func refresh() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let showItem = NSMenuItem(
            title: "Show Window Switcher",
            action: #selector(showSwitcher),
            keyEquivalent: ""
        )
        showItem.target = self
        showItem.image = menuIcon("rectangle.grid.2x2")
        menu.addItem(showItem)

        let settings = settingsStore.load()
        let enabledItem = NSMenuItem(
            title: "Replace Command-Tab",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = settings.isEnabled ? .on : .off
        enabledItem.image = menuIcon("command")
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        preferencesItem.image = menuIcon("gearshape")
        menu.addItem(preferencesItem)

        addPermissionItems(to: menu)
        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Startup",
            action: #selector(toggleLaunchAtStartup),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        launchItem.image = menuIcon("power")
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Window Switcher",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = menuIcon("xmark.circle")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func addPermissionItems(to menu: NSMenu) {
        let permissions = permissionsService.snapshot()
        var items: [NSMenuItem] = []

        if permissions.accessibility != .granted {
            items.append(permissionItem("Grant Accessibility…", "accessibility", #selector(requestAccessibility)))
        }
        if permissions.inputMonitoring != .granted {
            items.append(permissionItem("Open Input Monitoring…", "keyboard.badge.ellipsis", #selector(openInputMonitoring)))
        }
        if permissions.screenRecording != .granted {
            items.append(permissionItem("Grant Screen Recording…", "rectangle.inset.filled.badge.record", #selector(requestScreenRecording)))
        }

        if !items.isEmpty {
            menu.addItem(.separator())
            items.forEach(menu.addItem)
        }
    }

    private func permissionItem(_ title: String, _ symbol: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = menuIcon(symbol)
        return item
    }

    private func menuIcon(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func showSwitcher() {
        delegate?.showSwitcher()
    }

    @objc private func toggleEnabled() {
        let enabled = !settingsStore.load().isEnabled
        delegate?.setSwitcherEnabled(enabled)
    }

    @objc private func showPreferences() {
        delegate?.showPreferences()
    }

    @objc private func requestAccessibility() {
        delegate?.requestAccessibility()
    }

    @objc private func openInputMonitoring() {
        delegate?.openInputMonitoringSettings()
    }

    @objc private func requestScreenRecording() {
        delegate?.requestScreenRecording()
    }

    @objc private func toggleLaunchAtStartup() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            switcherLog("Launch at startup update failed: \(error.localizedDescription)")
        }
        refresh()
    }

    @objc private func quit() {
        delegate?.quitApplication()
    }
}
