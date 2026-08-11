import AppCore
import Foundation

@main
enum ValidationRunner {
    static func main() throws {
        try validateSettingsPersistence()
        validateWindowDisplayTitles()
        validateWindowRecordMatching()
        validateFocusedWindowMatching()
        validatePointerDisplaySelection()
        validateInitialWindowSelection()
        validateRepeatedWindowSwitching()
        validateEventDrivenWindowSwitching()
        validateTransientWindowDiscovery()
        validateMinimizedWindowOrdering()
        validateWindowPresentationFiltering()
        validateWindowPreviewLayout()
        validateWindowApplicationEligibility()
        validateAccessoryWindowScanCache()
        validateLiveRefreshCadence()
        validateDockPreviewCadence()
        validateDockPreviewOrdering()
        validateFullScreenActivationPlan()
        print("All validations passed.")
    }

    private static func validateSettingsPersistence() throws {
        let suiteName = "WindowSwitcherValidation-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults suite")
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        expect(store.load() == .default, "New settings store should return defaults")

        defaults.set(
            Data(
                """
                {
                  "isEnabled": false,
                  "includeMinimizedWindows": true,
                  "showWindowTitles": false
                }
                """.utf8
            ),
            forKey: "switcherSettings"
        )
        let migrated = store.load()
        expect(!migrated.isEnabled, "Existing enabled preference should survive migration")
        expect(
            !migrated.dockWindowPreviewsEnabled,
            "Dock previews should remain disabled when loading older settings"
        )

        let updated = SwitcherSettings(
            isEnabled: false,
            includeMinimizedWindows: false,
            showWindowTitles: false,
            dockWindowPreviewsEnabled: true
        )
        try store.save(updated)
        expect(store.load() == updated, "Settings should survive a store round trip")
    }

    private static func validateDockPreviewCadence() {
        expect(
            DockPreviewTiming.hoverDetectionDebounce + DockPreviewTiming.hoverIntentDelay
                <= DockPreviewTiming.maximumSnappyIntentLatency,
            "Dock hover intent should be recognized within 200 ms"
        )
    }

    private static func validateDockPreviewOrdering() {
        expect(
            DockPreviewOrdering.identifiers(
                discoveredIdentifiers: ["new", "first", "second"],
                previouslyDisplayedIdentifiers: ["first", "second"],
                creationOrderedIdentifiers: ["first", "second", "new"]
            ) == ["first", "second", "new"],
            "New Dock windows should be appended on the right"
        )
        expect(
            DockPreviewOrdering.identifiers(
                discoveredIdentifiers: ["second", "first"],
                previouslyDisplayedIdentifiers: [],
                creationOrderedIdentifiers: ["first", "second"]
            ) == ["first", "second"],
            "Initial Dock windows should follow creation order"
        )
        expect(
            DockPreviewOrdering.identifiers(
                discoveredIdentifiers: ["second", "first"],
                previouslyDisplayedIdentifiers: ["first", "second"],
                creationOrderedIdentifiers: ["second", "first"]
            ) == ["first", "second"],
            "Dock ordering should not change while the picker is open"
        )
    }

    private static func validateWindowDisplayTitles() {
        expect(
            WindowDisplayTitle.resolve(windowTitle: "  Roadmap  ", appName: "Notes") == "Roadmap",
            "Window titles should be trimmed"
        )
        expect(
            WindowDisplayTitle.resolve(windowTitle: "  ", appName: "Finder") == "Finder",
            "Untitled windows should fall back to their app name"
        )
    }

    private static func validateWindowRecordMatching() {
        let accessibilityWindow = WindowMatchDescriptor(
            processIdentifier: 42,
            title: "Project Roadmap",
            bounds: CGRect(x: 120, y: 80, width: 1280, height: 720)
        )
        let records = [
            WindowMatchDescriptor(
                processIdentifier: 7,
                title: "Project Roadmap",
                bounds: accessibilityWindow.bounds
            ),
            WindowMatchDescriptor(
                processIdentifier: 42,
                title: "Other Window",
                bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
            ),
            WindowMatchDescriptor(
                processIdentifier: 42,
                title: "Project Roadmap",
                bounds: CGRect(x: 121, y: 81, width: 1278, height: 718)
            ),
        ]

        expect(
            WindowRecordMatcher.bestMatchIndex(
                for: accessibilityWindow,
                in: records
            ) == 2,
            "An AX window without an ID should match its Window Server preview record"
        )
    }

    private static func validateFocusedWindowMatching() {
        let focusedWindow = WindowMatchDescriptor(
            processIdentifier: 42,
            title: "Terminal",
            bounds: CGRect(x: 100, y: 80, width: 1200, height: 800)
        )
        let candidates = [
            IdentifiedWindowMatchDescriptor(
                identifier: "42-100",
                descriptor: WindowMatchDescriptor(
                    processIdentifier: 42,
                    title: "Other",
                    bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
                )
            ),
            IdentifiedWindowMatchDescriptor(
                identifier: "42-101",
                descriptor: focusedWindow
            ),
        ]

        expect(
            FocusedWindowMatcher.identifier(
                explicitIdentifier: nil,
                focusedWindow: focusedWindow,
                candidates: candidates
            ) == "42-101",
            "A focused AX window without AXWindowNumber should match its discovered window"
        )
    }

    private static func validatePointerDisplaySelection() {
        expect(
            PointerDisplaySelection.index(
                at: CGPoint(x: 2_800, y: 500),
                displayFrames: [
                    CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
                    CGRect(x: 2_560, y: 0, width: 2_560, height: 1_440),
                ]
            ) == 1,
            "The switcher should open on the display containing the pointer"
        )
    }

    private static func validateInitialWindowSelection() {
        expect(
            InitialWindowSelection.index(windowCount: 5, movingForward: true) == 1,
            "Command-Tab should initially select the previous window"
        )
        expect(
            InitialWindowSelection.index(windowCount: 5, movingForward: false) == 4,
            "Command-Shift-Tab should initially select the last window"
        )
    }

    private static func validateRepeatedWindowSwitching() {
        let discoveredOrder = ["current", "previous", "older"]
        var recency = WindowSwitchRecency()
        var displayedOrder = recency.reconcile(
            discoveredWindowIdentifiers: discoveredOrder,
            currentWindowIdentifier: "current"
        )
        expect(
            displayedOrder == ["current", "previous", "older"],
            "Initial discovery should retain Window Server order"
        )

        recency.recordSelection("previous")
        displayedOrder = recency.reconcile(
            discoveredWindowIdentifiers: discoveredOrder,
            currentWindowIdentifier: "previous"
        )
        expect(
            displayedOrder == ["previous", "current", "older"],
            "The selected window should move first and the window left behind should move second"
        )

        recency.recordSelection("current")
        displayedOrder = recency.reconcile(
            discoveredWindowIdentifiers: discoveredOrder,
            currentWindowIdentifier: "current"
        )
        expect(
            displayedOrder == ["current", "previous", "older"],
            "Repeated Command-Tab gestures should reorder the two recent windows"
        )

        displayedOrder = recency.reconcile(
            discoveredWindowIdentifiers: ["current", "older", "new"],
            currentWindowIdentifier: "current"
        )
        expect(
            displayedOrder == ["current", "older", "new"],
            "Closed windows should be removed and new windows should join the end"
        )

        displayedOrder = recency.reconcile(
            discoveredWindowIdentifiers: ["current", "older", "new"],
            currentWindowIdentifier: "new"
        )
        expect(
            displayedOrder == ["new", "current", "older"],
            "Focusing a window outside the switcher should promote it to the front"
        )
    }

    private static func validateEventDrivenWindowSwitching() {
        var recency = WindowSwitchRecency()
        recency.recordActivation("teams")
        recency.recordActivation("browser")

        let displayedOrder = recency.reconcile(
            discoveredWindowIdentifiers: ["devbox", "terminal", "teams", "browser"],
            currentWindowIdentifier: "browser"
        )
        expect(
            displayedOrder == ["browser", "teams", "devbox", "terminal"],
            "Observed activation events should define MRU order independently of discovery order"
        )
    }

    private static func validateTransientWindowDiscovery() {
        var recency = WindowSwitchRecency()
        _ = recency.reconcile(
            discoveredWindowIdentifiers: ["current", "previous", "older"],
            currentWindowIdentifier: "current"
        )
        recency.recordSelection("previous")

        _ = recency.reconcile(
            discoveredWindowIdentifiers: ["previous", "older"],
            currentWindowIdentifier: "previous"
        )
        let restoredOrder = recency.reconcile(
            discoveredWindowIdentifiers: ["previous", "current", "older"],
            currentWindowIdentifier: "previous"
        )

        expect(
            restoredOrder == ["previous", "current", "older"],
            "A transient discovery miss should not reset a window's MRU position"
        )

        for _ in 0..<4 {
            _ = recency.reconcile(
                discoveredWindowIdentifiers: ["previous", "older"],
                currentWindowIdentifier: "previous"
            )
        }

        let orderAfterClose = recency.reconcile(
            discoveredWindowIdentifiers: ["previous", "older", "new"],
            currentWindowIdentifier: "previous"
        )
        expect(
            orderAfterClose == ["previous", "older", "new"],
            "A window missing for multiple refreshes should be removed from MRU history"
        )
    }

    private static func validateMinimizedWindowOrdering() {
        var recency = WindowSwitchRecency()
        let displayedOrder = recency.reconcile(
            discoveredWindowIdentifiers: ["current", "minimized", "previous"],
            currentWindowIdentifier: "current",
            minimizedWindowIdentifiers: ["minimized"]
        )

        expect(
            displayedOrder == ["current", "previous", "minimized"],
            "Minimized windows should move to the end of the MRU list"
        )
    }

    private static func validateWindowPresentationFiltering() {
        expect(
            !WindowPresentationFilter.shouldInclude(
                hasPreview: false,
                screenCaptureGranted: true
            ),
            "Icon-only AX entries should be hidden when real previews are available"
        )
        expect(
            WindowPresentationFilter.shouldInclude(
                hasPreview: false,
                screenCaptureGranted: false
            ),
            "Permission setup should retain icon fallbacks until capture is granted"
        )
    }

    private static func validateWindowPreviewLayout() {
        expect(
            WindowPreviewLayout.shouldFit(
                windowBounds: CGRect(x: 0, y: 0, width: 900, height: 700),
                previewSize: CGSize(width: 300, height: 169)
            ),
            "Compact settings windows should fit without cropping"
        )
        expect(
            !WindowPreviewLayout.shouldFit(
                windowBounds: CGRect(x: 0, y: 0, width: 1600, height: 900),
                previewSize: CGSize(width: 300, height: 169)
            ),
            "Display-shaped windows should continue filling their cards"
        )
    }

    private static func validateWindowApplicationEligibility() {
        expect(
            WindowApplicationEligibility.shouldInclude(
                isCurrentApplication: false,
                isTerminated: false,
                kind: .accessory,
                ownsWindowServerRecord: true
            ),
            "Menu bar app windows should be eligible for the switcher"
        )
        expect(
            !WindowApplicationEligibility.shouldInclude(
                isCurrentApplication: false,
                isTerminated: false,
                kind: .accessory,
                ownsWindowServerRecord: false
            ),
            "Menu bar agents without windows should not receive AX queries"
        )
        expect(
            !WindowApplicationEligibility.shouldInclude(
                isCurrentApplication: false,
                isTerminated: false,
                kind: .prohibited,
                ownsWindowServerRecord: true
            ),
            "Background and system processes should remain excluded"
        )
        expect(
            !WindowApplicationEligibility.shouldInclude(
                isCurrentApplication: true,
                isTerminated: false,
                kind: .accessory,
                ownsWindowServerRecord: true
            ),
            "The switcher should not list its own windows"
        )
        expect(
            !WindowApplicationEligibility.shouldInclude(
                isCurrentApplication: false,
                isTerminated: true,
                kind: .regular,
                ownsWindowServerRecord: true
            ),
            "Terminated applications should remain excluded"
        )
    }

    private static func validateAccessoryWindowScanCache() {
        var cache = AccessoryWindowScanCache()
        let originalWindowIdentifiers: Set<UInt32> = [10]

        expect(
            cache.shouldInspect(
                processIdentifier: 42,
                windowIdentifiers: originalWindowIdentifiers
            ),
            "An accessory app should be inspected before it is cached"
        )
        cache.recordResult(
            processIdentifier: 42,
            windowIdentifiers: originalWindowIdentifiers,
            foundAccessibilityWindow: false
        )
        expect(
            !cache.shouldInspect(
                processIdentifier: 42,
                windowIdentifiers: originalWindowIdentifiers
            ),
            "An unchanged accessory app without AX windows should be skipped"
        )
        expect(
            cache.shouldInspect(
                processIdentifier: 42,
                windowIdentifiers: [10, 11]
            ),
            "A changed Window Server signature should trigger another AX inspection"
        )
    }

    private static func validateLiveRefreshCadence() {
        expect(
            WindowLiveRefresh.interval >= 0.5,
            "Live refresh should leave enough main-thread time for keyboard navigation"
        )
    }

    private static func validateFullScreenActivationPlan() {
        expect(
            WindowActivationPlan.fullScreenSafe == [
                .unminimize,
                .frontProcessWithWindowIdentifier,
                .makeWindowKey,
                .activateApplication,
                .resolveCrossSpaceAccessibility,
                .raiseWindow,
            ],
            "Full-screen activation must target the selected Window Server ID"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
