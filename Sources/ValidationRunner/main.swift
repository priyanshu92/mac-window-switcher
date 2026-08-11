import AppCore
import Foundation

@main
enum ValidationRunner {
    static func main() throws {
        try validateSettingsPersistence()
        validateWindowDisplayTitles()
        validateWindowRecordMatching()
        validateInitialWindowSelection()
        validateRepeatedWindowSwitching()
        validateWindowPresentationFiltering()
        validateWindowPreviewLayout()
        validateWindowApplicationEligibility()
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

        let updated = SwitcherSettings(
            isEnabled: false,
            includeMinimizedWindows: false,
            showWindowTitles: false
        )
        try store.save(updated)
        expect(store.load() == updated, "Settings should survive a store round trip")
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
                kind: .accessory
            ),
            "Menu bar app windows should be eligible for the switcher"
        )
        expect(
            !WindowApplicationEligibility.shouldInclude(
                isCurrentApplication: false,
                isTerminated: false,
                kind: .prohibited
            ),
            "Background and system processes should remain excluded"
        )
        expect(
            !WindowApplicationEligibility.shouldInclude(
                isCurrentApplication: true,
                isTerminated: false,
                kind: .accessory
            ),
            "The switcher should not list its own windows"
        )
        expect(
            !WindowApplicationEligibility.shouldInclude(
                isCurrentApplication: false,
                isTerminated: true,
                kind: .regular
            ),
            "Terminated applications should remain excluded"
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
