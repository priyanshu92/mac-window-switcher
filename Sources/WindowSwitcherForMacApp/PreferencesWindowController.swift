import AppCore
import AppKit
import PlatformServices

@MainActor
protocol PreferencesWindowControllerDelegate: AnyObject {
    func preferencesDidChange(_ settings: SwitcherSettings)
    func preferencesDidRequestPreview()
    func preferencesDidRequestAccessibility()
    func preferencesDidRequestScreenRecording()
    func preferencesDidRequestInputMonitoring()
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("WindowSwitcherPreferences")

    private let settingsStore: SwitcherSettingsStore
    private let permissionsService: PermissionsService
    private weak var delegate: PreferencesWindowControllerDelegate?

    private let enabledCheckbox = NSButton(checkboxWithTitle: "Replace Command-Tab", target: nil, action: nil)
    private let minimizedCheckbox = NSButton(checkboxWithTitle: "Include minimized windows", target: nil, action: nil)
    private let titlesCheckbox = NSButton(checkboxWithTitle: "Show window titles", target: nil, action: nil)
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let inputMonitoringStatus = NSTextField(labelWithString: "")
    private let screenRecordingStatus = NSTextField(labelWithString: "")

    init(
        settingsStore: SwitcherSettingsStore,
        permissionsService: PermissionsService,
        delegate: PreferencesWindowControllerDelegate
    ) {
        self.settingsStore = settingsStore
        self.permissionsService = permissionsService
        self.delegate = delegate

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Window Switcher"
        window.titlebarAppearsTransparent = true
        super.init(window: window)

        shouldCascadeWindows = false
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        configureUI(window)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        let settings = settingsStore.load()
        enabledCheckbox.state = settings.isEnabled ? .on : .off
        minimizedCheckbox.state = settings.includeMinimizedWindows ? .on : .off
        titlesCheckbox.state = settings.showWindowTitles ? .on : .off

        let permissions = permissionsService.snapshot()
        configureStatus(accessibilityStatus, permissions.accessibility, granted: "Ready to find and focus every app window.")
        configureStatus(inputMonitoringStatus, permissions.inputMonitoring, granted: "Ready to intercept Command-Tab.")
        configureStatus(screenRecordingStatus, permissions.screenRecording, granted: "Ready to render window previews.")
    }

    private func configureUI(_ window: NSWindow) {
        guard let content = window.contentView else { return }

        let title = NSTextField(labelWithString: "Switch by window, not just by app.")
        title.font = .systemFont(ofSize: 24, weight: .bold)

        let subtitle = NSTextField(wrappingLabelWithString: "Hold Command and tap Tab to move through a visual filmstrip of every open window. Release Command to focus the selection.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        [enabledCheckbox, minimizedCheckbox, titlesCheckbox].forEach {
            $0.target = self
            $0.action = #selector(saveSettings)
        }

        let behaviorStack = NSStackView(views: [enabledCheckbox, minimizedCheckbox, titlesCheckbox])
        behaviorStack.orientation = .vertical
        behaviorStack.alignment = .leading
        behaviorStack.addArrangedSubview(
            NSButton(
                title: "Preview Window Switcher",
                target: self,
                action: #selector(previewSwitcher)
            )
        )
        let behaviorBox = makeSection(title: "Behavior", content: behaviorStack)

        let permissionsStack = NSStackView()
        permissionsStack.orientation = .vertical
        permissionsStack.spacing = 14
        permissionsStack.addArrangedSubview(permissionRow(
            title: "Accessibility",
            detail: accessibilityStatus,
            buttonTitle: "Grant…",
            action: #selector(requestAccessibility)
        ))
        permissionsStack.addArrangedSubview(permissionRow(
            title: "Input Monitoring",
            detail: inputMonitoringStatus,
            buttonTitle: "Open Settings…",
            action: #selector(requestInputMonitoring)
        ))
        permissionsStack.addArrangedSubview(permissionRow(
            title: "Screen Recording",
            detail: screenRecordingStatus,
            buttonTitle: "Grant…",
            action: #selector(requestScreenRecording)
        ))
        let permissionsBox = makeSection(title: "Permissions", content: permissionsStack)

        let root = NSStackView(views: [title, subtitle, behaviorBox, permissionsBox])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            subtitle.widthAnchor.constraint(equalTo: root.widthAnchor),
            behaviorBox.widthAnchor.constraint(equalTo: root.widthAnchor),
            permissionsBox.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func makeSection(title: String, content: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor

        if let stack = content as? NSStackView {
            stack.spacing = 10
        }

        let section = NSStackView(views: [label, content])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        section.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        section.wantsLayer = true
        section.layer?.cornerRadius = 12
        section.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        return section
    }

    private func permissionRow(
        title: String,
        detail: NSTextField,
        buttonTitle: String,
        action: Selector
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [titleLabel, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        let button = NSButton(title: buttonTitle, target: self, action: action)
        let row = NSStackView(views: [labels, NSView(), button])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func configureStatus(_ label: NSTextField, _ status: PermissionStatus, granted: String) {
        switch status {
        case .granted:
            label.stringValue = granted
            label.textColor = .systemGreen
        case .notGranted:
            label.stringValue = "Required. Grant access, then restart the app."
            label.textColor = .systemOrange
        case .requiresManualGrant:
            label.stringValue = "Open System Settings and enable this app."
            label.textColor = .systemOrange
        }
    }

    @objc private func saveSettings() {
        let settings = SwitcherSettings(
            isEnabled: enabledCheckbox.state == .on,
            includeMinimizedWindows: minimizedCheckbox.state == .on,
            showWindowTitles: titlesCheckbox.state == .on
        )
        do {
            try settingsStore.save(settings)
            delegate?.preferencesDidChange(settings)
        } catch {
            switcherLog("Saving preferences failed: \(error.localizedDescription)")
        }
    }

    @objc private func requestAccessibility() {
        delegate?.preferencesDidRequestAccessibility()
    }

    @objc private func previewSwitcher() {
        delegate?.preferencesDidRequestPreview()
    }

    @objc private func requestInputMonitoring() {
        delegate?.preferencesDidRequestInputMonitoring()
    }

    @objc private func requestScreenRecording() {
        delegate?.preferencesDidRequestScreenRecording()
    }
}
