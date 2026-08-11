import AppCore
import AppKit
import PlatformServices
import SwiftUI

@MainActor
final class SwitcherController {
    private static let cardSpacing: CGFloat = 12
    private static let panelPadding: CGFloat = 18
    private static let captionHeight: CGFloat = 44

    private let windowService: MacWindowService
    private let settingsStore: SwitcherSettingsStore
    private let viewModel = SwitcherViewModel()
    private let panel: NSPanel
    private var hostingController: NSHostingController<SwitcherView>!
    private var liveRefreshTimer: Timer?
    private var sessionScreen: NSScreen?
    private var sessionOriginWindowIdentifier: String?
    private var windowSwitchRecency = WindowSwitchRecency()

    init(windowService: MacWindowService, settingsStore: SwitcherSettingsStore) {
        self.windowService = windowService
        self.settingsStore = settingsStore

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 288, height: 306),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        let view = SwitcherView(model: viewModel) { [weak self] index in
            self?.selectAndCommit(index)
        }
        hostingController = NSHostingController(rootView: view)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.layer?.cornerRadius = 34
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true
        panel.contentViewController = hostingController
    }

    func handle(_ gesture: CommandTabGesture) {
        switch gesture {
        case .cycleForward:
            cycle(by: 1)
        case .cycleBackward:
            cycle(by: -1)
        case .commit:
            commit()
        case .cancel:
            cancel()
        case .quitSelected:
            quitSelectedApplication()
        }
    }

    func showForMenu() {
        loadWindows(preservingSelection: false)
        viewModel.selectedIndex = 0
        showPanel()
    }

    func cancel() {
        stopLiveUpdates()
        panel.orderOut(nil)
        viewModel.windows = []
        sessionScreen = nil
        sessionOriginWindowIdentifier = nil
    }

    private func cycle(by offset: Int) {
        if !panel.isVisible {
            loadWindows(preservingSelection: false)
            guard !viewModel.windows.isEmpty else {
                showPanel()
                return
            }

            sessionOriginWindowIdentifier = viewModel.windows.first?.id
            viewModel.selectedIndex = InitialWindowSelection.index(
                windowCount: viewModel.windows.count,
                movingForward: offset > 0
            )
            showPanel()
            return
        }

        guard !viewModel.windows.isEmpty else { return }
        viewModel.selectedIndex = (
            viewModel.selectedIndex + offset + viewModel.windows.count
        ) % viewModel.windows.count
    }

    private func loadWindows(preservingSelection: Bool) {
        let selectedIdentifier = preservingSelection ? viewModel.selectedWindow?.id : nil
        let settings = settingsStore.load()
        viewModel.showWindowTitles = settings.showWindowTitles
        let discoveredWindows = windowService.discoverWindows(
            includeMinimized: settings.includeMinimizedWindows
        )
        let windowsByIdentifier = Dictionary(
            uniqueKeysWithValues: discoveredWindows.map { ($0.id, $0) }
        )
        let discoveredIdentifiers = discoveredWindows.map(\.id)
        let currentIdentifier = panel.isVisible
            ? sessionOriginWindowIdentifier
            : windowService.focusedWindowIdentifier(in: discoveredWindows)
        let orderedIdentifiers = windowSwitchRecency.reconcile(
            discoveredWindowIdentifiers: discoveredIdentifiers,
            currentWindowIdentifier: currentIdentifier,
            minimizedWindowIdentifiers: Set(
                discoveredWindows.lazy.filter(\.isMinimized).map(\.id)
            ),
            synchronizeWithDiscoveredOrder: !panel.isVisible
        )
        viewModel.windows = orderedIdentifiers.compactMap { windowsByIdentifier[$0] }

        if
            let selectedIdentifier,
            let updatedIndex = viewModel.windows.firstIndex(where: { $0.id == selectedIdentifier })
        {
            viewModel.selectedIndex = updatedIndex
        } else {
            viewModel.selectedIndex = min(
                viewModel.selectedIndex,
                max(viewModel.windows.count - 1, 0)
            )
        }

        if panel.isVisible {
            sizeAndPositionPanel()
        }
    }

    private func showPanel() {
        sessionScreen = screenContainingCurrentWindow()
        sizeAndPositionPanel()
        panel.orderFrontRegardless()
        startLiveUpdates()
    }

    private func sizeAndPositionPanel() {
        let screen = sessionScreen ?? screenContainingCurrentWindow()
        guard let visibleFrame = screen?.visibleFrame else { return }

        let availableWidth = max(1, visibleFrame.width - 64)
        let availableHeight = max(1, visibleFrame.height - 64)
        let screenAspectRatio = displayAspectRatio(for: screen) ?? (16.0 / 9.0)
        var cardWidth = min(300, max(210, visibleFrame.width / 5.5))
        var previewHeight = cardWidth / screenAspectRatio
        var columnCount = 1
        var rowCount = 1
        var panelHeight = CGFloat.greatestFiniteMagnitude

        repeat {
            let maximumColumns = max(
                1,
                Int(
                    (availableWidth - Self.panelPadding * 2 + Self.cardSpacing)
                        / (cardWidth + Self.cardSpacing)
                )
            )
            columnCount = min(maximumColumns, max(viewModel.windows.count, 1))
            rowCount = Int(
                ceil(Double(max(viewModel.windows.count, 1)) / Double(columnCount))
            )
            previewHeight = cardWidth / screenAspectRatio
            let cardHeight = Self.captionHeight + previewHeight
            panelHeight = Self.panelPadding * 2
                + CGFloat(rowCount) * cardHeight
                + CGFloat(max(rowCount - 1, 0)) * Self.cardSpacing
            if panelHeight <= availableHeight || cardWidth <= 150 {
                break
            }
            cardWidth -= 8
        } while true

        viewModel.columnCount = columnCount
        viewModel.cardWidth = cardWidth
        viewModel.previewHeight = previewHeight

        let width = Self.panelPadding * 2
            + CGFloat(columnCount) * cardWidth
            + CGFloat(max(columnCount - 1, 0)) * Self.cardSpacing
        panel.setContentSize(NSSize(width: width, height: panelHeight))

        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - panelHeight / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func commit() {
        guard panel.isVisible, let selected = viewModel.selectedWindow else {
            cancel()
            return
        }

        stopLiveUpdates()
        panel.orderOut(nil)
        windowSwitchRecency.recordSelection(selected.id)
        windowService.activate(selected)
        viewModel.windows = []
        sessionScreen = nil
        sessionOriginWindowIdentifier = nil
    }

    private func selectAndCommit(_ index: Int) {
        guard viewModel.windows.indices.contains(index) else { return }
        viewModel.selectedIndex = index
        commit()
    }

    private func quitSelectedApplication() {
        guard let selected = viewModel.selectedWindow else { return }
        windowService.quitApplication(owning: selected)
    }

    private func startLiveUpdates() {
        guard liveRefreshTimer == nil else { return }

        let timer = Timer(timeInterval: WindowLiveRefresh.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.loadWindows(preservingSelection: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveRefreshTimer = timer
    }

    private func stopLiveUpdates() {
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
    }

    private func screenContainingCurrentWindow() -> NSScreen? {
        guard let currentWindow = viewModel.windows.first else {
            let mouseLocation = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        }

        let center = CGPoint(x: currentWindow.bounds.midX, y: currentWindow.bounds.midY)
        return NSScreen.screens.first { screen in
            guard let displayID = displayID(for: screen) else { return false }
            return CGDisplayBounds(displayID).contains(center)
        } ?? NSScreen.main
    }

    private func displayAspectRatio(for screen: NSScreen?) -> CGFloat? {
        guard
            let screen,
            let displayID = displayID(for: screen)
        else {
            return nil
        }
        let bounds = CGDisplayBounds(displayID)
        guard bounds.height > 0 else { return nil }
        return bounds.width / bounds.height
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
