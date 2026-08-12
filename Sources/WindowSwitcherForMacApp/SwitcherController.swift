import AppCore
import AppKit
import PlatformServices
import SwiftUI

enum DockClickResult {
    case noWindows
    case activatedWindow
    case presentedWindows
}

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
    private var activityTrackingTimer: Timer?
    private var lastObservedActiveWindowIdentifier: String?
    private var sessionScreen: NSScreen?
    private var sessionOriginWindowIdentifier: String?
    private var dockProcessIdentifier: pid_t?
    private var dockAnchorPoint: NSPoint?
    private var dockOriginActivationTarget: WindowActivationTarget?
    private var dockHoveredWindowIdentifier: String?
    private var dockRestoreTask: Task<Void, Never>?
    private var suppressedDockWindowIdentifiers: Set<String> = []
    private var cachedGlobalWindows: [SwitchableWindow] = []
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

        let view = SwitcherView(
            model: viewModel,
            onSelect: { [weak self] index in
                self?.selectAndCommit(index)
            },
            onHover: { [weak self] index in
                self?.previewDockWindow(at: index)
            },
            onClose: { [weak self] index in
                self?.closeDockWindow(at: index)
            }
        )
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

    func startActivityTracking() {
        guard activityTrackingTimer == nil else { return }

        observeActiveWindow()
        let timer = Timer(timeInterval: WindowActivityTracking.interval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.observeActiveWindow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        activityTrackingTimer = timer
    }

    func observeActiveWindow() {
        guard
            !panel.isVisible,
            let identifier = windowService.activeWindowIdentifier(),
            identifier != lastObservedActiveWindowIdentifier
        else {
            return
        }
        lastObservedActiveWindowIdentifier = identifier
        windowSwitchRecency.recordActivation(identifier)
    }

    func showForMenu() {
        prepareSession()
        loadWindows(preservingSelection: false)
        viewModel.selectedIndex = 0
        showPanel()
    }

    func showDockWindows(processIdentifier: pid_t) -> Bool {
        prepareDockSession(processIdentifier: processIdentifier)
        loadWindows(preservingSelection: false)
        guard !viewModel.windows.isEmpty else {
            cancel()
            return false
        }

        viewModel.selectedIndex = -1
        showPanel()
        return true
    }

    func handleDockClick(processIdentifier: pid_t) -> DockClickResult {
        prepareDockSession(processIdentifier: processIdentifier)
        loadWindows(preservingSelection: false)

        switch viewModel.windows.count {
        case 0:
            cancel()
            return .noWindows
        case 1:
            let window = viewModel.windows[0]
            windowSwitchRecency.recordSelection(window.id)
            clearSession(restoringDockOrigin: false)
            windowService.activate(window)
            return .activatedWindow
        default:
            viewModel.selectedIndex = -1
            showPanel()
            return .presentedWindows
        }
    }

    func dismissDockPreview() {
        guard dockProcessIdentifier != nil else { return }
        cancel()
    }

    func isShowingDockWindows(processIdentifier: pid_t) -> Bool {
        panel.isVisible && dockProcessIdentifier == processIdentifier
    }

    func isPointerInsideDockPanel() -> Bool {
        guard panel.isVisible, dockProcessIdentifier != nil else { return false }
        return panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
    }

    func cancel() {
        clearSession(restoringDockOrigin: dockProcessIdentifier != nil)
    }

    private func clearSession(restoringDockOrigin: Bool) {
        dockRestoreTask?.cancel()
        dockRestoreTask = nil
        let activationTarget = restoringDockOrigin ? dockOriginActivationTarget : nil
        stopLiveUpdates()
        panel.orderOut(nil)
        viewModel.windows = []
        sessionScreen = nil
        sessionOriginWindowIdentifier = nil
        dockProcessIdentifier = nil
        dockAnchorPoint = nil
        dockOriginActivationTarget = nil
        dockHoveredWindowIdentifier = nil
        suppressedDockWindowIdentifiers.removeAll()
        viewModel.isDockPreview = false
        viewModel.showsCloseButtons = false
        hostingController.view.layer?.masksToBounds = true
        panel.hasShadow = true
        if let activationTarget {
            windowService.activate(activationTarget)
        }
    }

    private func cycle(by offset: Int) {
        if dockProcessIdentifier != nil {
            cancel()
        }

        if !panel.isVisible {
            prepareSession()
            if !cachedGlobalWindows.isEmpty {
                applyGlobalWindows(
                    cachedGlobalWindows,
                    selectedIdentifier: nil
                )
                sessionOriginWindowIdentifier = viewModel.windows.first?.id
                viewModel.selectedIndex = InitialWindowSelection.index(
                    windowCount: viewModel.windows.count,
                    movingForward: offset > 0
                )
                showPanel()
                return
            }
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
        let shouldRefreshPreviews =
            panel.isVisible
            || dockProcessIdentifier != nil
            || InitialWindowDiscovery.shouldRefreshPreviews(
                hasCachedWindows: !cachedGlobalWindows.isEmpty
            )
        let discoveredWindows = windowService.discoverWindows(
            includeMinimized: settings.includeMinimizedWindows,
            processIdentifier: dockProcessIdentifier,
            refreshPreviews: shouldRefreshPreviews,
            previewRefreshLimit:
                panel.isVisible && dockProcessIdentifier == nil ? 4 : nil
        )
        if dockProcessIdentifier != nil {
            let discoveredIdentifiers = discoveredWindows.map(\.id)
            suppressedDockWindowIdentifiers = suppressedDockWindowIdentifiers.filter {
                discoveredIdentifiers.contains($0)
            }
            let availableWindows = discoveredWindows.filter {
                !suppressedDockWindowIdentifiers.contains($0.id)
            }
            let windowsByIdentifier = Dictionary(
                uniqueKeysWithValues: availableWindows.map { ($0.id, $0) }
            )
            let discoveryRanks = Dictionary(
                uniqueKeysWithValues: availableWindows.enumerated().map {
                    ($0.element.id, $0.offset)
                }
            )
            let creationOrderedIdentifiers = availableWindows.sorted { lhs, rhs in
                switch (lhs.windowIdentifier, rhs.windowIdentifier) {
                case let (lhsIdentifier?, rhsIdentifier?)
                    where lhsIdentifier != rhsIdentifier:
                    return lhsIdentifier < rhsIdentifier
                default:
                    return discoveryRanks[lhs.id, default: Int.max]
                        < discoveryRanks[rhs.id, default: Int.max]
                }
            }.map(\.id)
            let orderedIdentifiers = DockPreviewOrdering.identifiers(
                discoveredIdentifiers: availableWindows.map(\.id),
                previouslyDisplayedIdentifiers: viewModel.windows.map(\.id),
                creationOrderedIdentifiers: creationOrderedIdentifiers
            )
            viewModel.windows = orderedIdentifiers.compactMap {
                windowsByIdentifier[$0]
            }
            updateSelection(selectedIdentifier: selectedIdentifier)
            if panel.isVisible {
                sizeAndPositionPanel()
            }
            return
        }

        cachedGlobalWindows = discoveredWindows
        applyGlobalWindows(
            discoveredWindows,
            selectedIdentifier: selectedIdentifier
        )

        if panel.isVisible {
            sizeAndPositionPanel()
        }
    }

    private func applyGlobalWindows(
        _ discoveredWindows: [SwitchableWindow],
        selectedIdentifier: String?
    ) {
        let windowsByIdentifier = Dictionary(
            uniqueKeysWithValues: discoveredWindows.map { ($0.id, $0) }
        )
        let discoveredIdentifiers = discoveredWindows.map(\.id)
        let currentIdentifier: String?
        if dockProcessIdentifier != nil {
            currentIdentifier = nil
        } else {
            currentIdentifier = panel.isVisible
                ? sessionOriginWindowIdentifier
                : windowService.focusedWindowIdentifier(in: discoveredWindows)
        }
        let orderedIdentifiers = windowSwitchRecency.reconcile(
            discoveredWindowIdentifiers: discoveredIdentifiers,
            currentWindowIdentifier: currentIdentifier,
            minimizedWindowIdentifiers: Set(
                discoveredWindows.lazy.filter(\.isMinimized).map(\.id)
            )
        )
        viewModel.windows = orderedIdentifiers
            .compactMap { windowsByIdentifier[$0] }

        updateSelection(selectedIdentifier: selectedIdentifier)
    }

    private func updateSelection(selectedIdentifier: String?) {
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
    }

    private func showPanel() {
        sizeAndPositionPanel()
        panel.orderFrontRegardless()
        startLiveUpdates()
    }

    private func sizeAndPositionPanel(animated: Bool = false) {
        let screen = sessionScreen ?? screenContainingPointer()
        guard let visibleFrame = screen?.visibleFrame else { return }

        let panelPadding = dockProcessIdentifier == nil
            ? Self.panelPadding
            : DockWindowPreviewLayout.panelPadding
        let cardSpacing = dockProcessIdentifier == nil ? Self.cardSpacing : 8
        let availableWidth = max(1, visibleFrame.width - 64)
        let availableHeight = max(1, visibleFrame.height - 64)
        let screenAspectRatio = displayAspectRatio(for: screen) ?? (16.0 / 9.0)

        if dockProcessIdentifier != nil {
            let windowCount = max(viewModel.windows.count, 1)
            let spacingWidth = CGFloat(max(windowCount - 1, 0)) * cardSpacing
            let fixedWidth = panelPadding * 2
                + spacingWidth
                + CGFloat(windowCount) * DockWindowPreviewLayout.horizontalChrome
            let aspectRatioSum = viewModel.windows.reduce(CGFloat.zero) {
                $0 + DockWindowPreviewLayout.aspectRatio(windowSize: $1.bounds.size)
            }
            let targetPreviewHeight = min(
                120,
                max(96, visibleFrame.height / 8)
            )
            let maximumContentHeight = aspectRatioSum > 0
                ? (availableWidth - fixedWidth) / aspectRatioSum
                : targetPreviewHeight - DockWindowPreviewLayout.bottomChrome
            let contentHeight = min(
                targetPreviewHeight - DockWindowPreviewLayout.bottomChrome,
                max(64, maximumContentHeight)
            )
            let dockPreviewHeight =
                contentHeight + DockWindowPreviewLayout.bottomChrome
            let cardWidths = viewModel.windows.map {
                DockWindowPreviewLayout.cardWidth(
                    windowSize: $0.bounds.size,
                    previewHeight: dockPreviewHeight
                )
            }
            let width = panelPadding * 2
                + cardWidths.reduce(0, +)
                + spacingWidth
            let panelHeight = panelPadding * 2
                + Self.captionHeight
                + dockPreviewHeight

            viewModel.columnCount = windowCount
            viewModel.cardWidth = cardWidths.first ?? 200
            viewModel.previewHeight = dockPreviewHeight

            let origin = dockPanelOrigin(
                panelSize: NSSize(width: width, height: panelHeight),
                anchorPoint: dockAnchorPoint ?? NSEvent.mouseLocation,
                screenFrame: screen?.frame ?? visibleFrame,
                visibleFrame: visibleFrame
            )
            panel.setFrame(
                NSRect(
                    origin: origin,
                    size: NSSize(width: width, height: panelHeight)
                ),
                display: true
            )
            return
        }

        var cardWidth = dockProcessIdentifier == nil
            ? min(300, max(210, visibleFrame.width / 5.5))
            : min(228, max(172, visibleFrame.width / 7.5))
        var previewHeight = cardWidth / screenAspectRatio
        var columnCount = 1
        var rowCount = 1
        var panelHeight = CGFloat.greatestFiniteMagnitude

        repeat {
            let maximumColumns = max(
                1,
                Int(
                    (availableWidth - panelPadding * 2 + cardSpacing)
                        / (cardWidth + cardSpacing)
                )
            )
            columnCount = min(maximumColumns, max(viewModel.windows.count, 1))
            rowCount = Int(
                ceil(Double(max(viewModel.windows.count, 1)) / Double(columnCount))
            )
            previewHeight = cardWidth / screenAspectRatio
            let cardHeight = Self.captionHeight + previewHeight
            panelHeight = panelPadding * 2
                + CGFloat(rowCount) * cardHeight
                + CGFloat(max(rowCount - 1, 0)) * cardSpacing
            if panelHeight <= availableHeight || cardWidth <= 150 {
                break
            }
            cardWidth -= 8
        } while true

        viewModel.columnCount = columnCount
        viewModel.cardWidth = cardWidth
        viewModel.previewHeight = previewHeight

        let width = panelPadding * 2
            + CGFloat(columnCount) * cardWidth
            + CGFloat(max(columnCount - 1, 0)) * cardSpacing
        let origin: NSPoint
        if let dockAnchorPoint {
            origin = dockPanelOrigin(
                panelSize: NSSize(width: width, height: panelHeight),
                anchorPoint: dockAnchorPoint,
                screenFrame: screen?.frame ?? visibleFrame,
                visibleFrame: visibleFrame
            )
        } else {
            origin = NSPoint(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY - panelHeight / 2
            )
        }
        let frame = NSRect(
            origin: origin,
            size: NSSize(width: width, height: panelHeight)
        )
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func commit() {
        guard panel.isVisible, let selected = viewModel.selectedWindow else {
            cancel()
            return
        }

        windowSwitchRecency.recordSelection(selected.id)
        clearSession(restoringDockOrigin: false)
        windowService.activate(selected)
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

    private func prepareSession() {
        sessionScreen = screenContainingPointer()
        dockProcessIdentifier = nil
        dockAnchorPoint = nil
        dockOriginActivationTarget = nil
        viewModel.isDockPreview = false
        viewModel.showsCloseButtons = false
        hostingController.view.layer?.masksToBounds = true
        panel.hasShadow = true
        suppressedDockWindowIdentifiers.removeAll()
    }

    private func prepareDockSession(processIdentifier: pid_t) {
        if
            let dockProcessIdentifier,
            dockProcessIdentifier != processIdentifier
        {
            suppressedDockWindowIdentifiers.removeAll()
        }
        if dockOriginActivationTarget == nil {
            dockOriginActivationTarget = windowService.activeWindowTarget()
        }
        sessionScreen = screenContainingPointer()
        sessionOriginWindowIdentifier = nil
        dockProcessIdentifier = processIdentifier
        dockAnchorPoint = NSEvent.mouseLocation
        viewModel.isDockPreview = true
        viewModel.showsCloseButtons = true
        hostingController.view.layer?.masksToBounds = false
        panel.hasShadow = false
    }

    private func previewDockWindow(at index: Int?) {
        guard dockProcessIdentifier != nil, panel.isVisible else { return }

        dockRestoreTask?.cancel()
        dockRestoreTask = nil

        guard let index, viewModel.windows.indices.contains(index) else {
            dockHoveredWindowIdentifier = nil
            dockRestoreTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard
                    !Task.isCancelled,
                    let self,
                    self.dockHoveredWindowIdentifier == nil,
                    let activationTarget = self.dockOriginActivationTarget
                else {
                    return
                }
                self.windowService.activate(activationTarget)
                self.dockRestoreTask = nil
            }
            return
        }

        let window = viewModel.windows[index]
        guard dockHoveredWindowIdentifier != window.id else { return }
        dockHoveredWindowIdentifier = window.id
        windowService.activate(window)
    }

    private func closeDockWindow(at index: Int) {
        guard
            dockProcessIdentifier != nil,
            viewModel.windows.indices.contains(index)
        else {
            return
        }

        let window = viewModel.windows[index]
        suppressedDockWindowIdentifiers.insert(window.id)
        if dockHoveredWindowIdentifier == window.id {
            dockHoveredWindowIdentifier = nil
        }
        stopLiveUpdates()
        _ = withAnimation(.easeOut(duration: 0.14)) {
            viewModel.windows.remove(at: index)
        }
        if !viewModel.windows.isEmpty {
            sizeAndPositionPanel(animated: true)
        }
        windowService.close(window)
        previewDockWindow(at: nil)

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, self.dockProcessIdentifier != nil else { return }
            self.loadWindows(preservingSelection: false)
            if self.viewModel.windows.isEmpty {
                self.cancel()
            } else {
                self.startLiveUpdates()
            }
        }
    }

    private func dockPanelOrigin(
        panelSize: NSSize,
        anchorPoint: NSPoint,
        screenFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSPoint {
        let margin: CGFloat = 12
        let bottomInset = visibleFrame.minY - screenFrame.minY
        let leftInset = visibleFrame.minX - screenFrame.minX
        let rightInset = screenFrame.maxX - visibleFrame.maxX
        let largestInset = max(bottomInset, leftInset, rightInset)
        let dockIsOnLeft = largestInset > 1
            ? leftInset == largestInset
            : anchorPoint.x - screenFrame.minX < anchorPoint.y - screenFrame.minY
                && anchorPoint.x - screenFrame.minX < screenFrame.maxX - anchorPoint.x
        let dockIsOnRight = largestInset > 1
            ? rightInset == largestInset
            : screenFrame.maxX - anchorPoint.x < anchorPoint.y - screenFrame.minY
                && screenFrame.maxX - anchorPoint.x < anchorPoint.x - screenFrame.minX

        // Auto-hidden Docks do not reserve space in visibleFrame, so fall back
        // to the screen edge nearest the Dock icon under the pointer.
        if dockIsOnLeft {
            return NSPoint(
                x: visibleFrame.minX + margin,
                y: min(
                    max(anchorPoint.y - panelSize.height / 2, visibleFrame.minY),
                    visibleFrame.maxY - panelSize.height
                )
            )
        }

        if dockIsOnRight {
            return NSPoint(
                x: visibleFrame.maxX - panelSize.width - margin,
                y: min(
                    max(anchorPoint.y - panelSize.height / 2, visibleFrame.minY),
                    visibleFrame.maxY - panelSize.height
                )
            )
        }

        return NSPoint(
            x: min(
                max(anchorPoint.x - panelSize.width / 2, visibleFrame.minX),
                visibleFrame.maxX - panelSize.width
            ),
            y: visibleFrame.minY + margin
        )
    }

    private func screenContainingPointer() -> NSScreen? {
        let pointerLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard
            let index = PointerDisplaySelection.index(
                at: pointerLocation,
                displayFrames: screens.map(\.frame)
            )
        else {
            return NSScreen.main
        }
        return screens[index]
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
