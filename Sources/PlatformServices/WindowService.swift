import AppCore
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
public final class SwitchableWindow: Identifiable {
    public let id: String
    public let processIdentifier: pid_t
    public let windowIdentifier: CGWindowID?
    public let appName: String
    public let appIcon: NSImage
    public let windowTitle: String
    public let preview: NSImage?
    public let isMinimized: Bool
    public let bounds: CGRect

    var accessibilityElement: AXUIElement?

    fileprivate init(
        id: String,
        processIdentifier: pid_t,
        windowIdentifier: CGWindowID?,
        appName: String,
        appIcon: NSImage,
        windowTitle: String,
        preview: NSImage?,
        isMinimized: Bool,
        bounds: CGRect,
        accessibilityElement: AXUIElement?
    ) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.windowIdentifier = windowIdentifier
        self.appName = appName
        self.appIcon = appIcon
        self.windowTitle = WindowDisplayTitle.resolve(windowTitle: windowTitle, appName: appName)
        self.preview = preview
        self.isMinimized = isMinimized
        self.bounds = bounds
        self.accessibilityElement = accessibilityElement
    }
}

@MainActor
public final class MacWindowService {
    private struct CGWindowRecord {
        let identifier: CGWindowID
        let processIdentifier: pid_t
        let title: String
        let bounds: CGRect
        let order: Int

        var matchDescriptor: WindowMatchDescriptor {
            WindowMatchDescriptor(
                processIdentifier: processIdentifier,
                title: title,
                bounds: bounds
            )
        }
    }

    private var previewCache: [CGWindowID: NSImage] = [:]
    private var accessoryWindowScanCache = AccessoryWindowScanCache()

    public init() {}

    public func focusedWindowIdentifier() -> String? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard
            let focusedWindow = copyAttribute(
                applicationElement,
                attribute: kAXFocusedWindowAttribute as CFString,
                as: AXUIElement.self
            ),
            let identifier = windowIdentifier(for: focusedWindow)
        else {
            return nil
        }

        return "\(application.processIdentifier)-\(identifier)"
    }

    public func discoverWindows(includeMinimized: Bool) -> [SwitchableWindow] {
        let records = coreGraphicsWindowRecords()
        let currentIdentifiers = Set(records.map(\.identifier))
        previewCache = previewCache.filter { currentIdentifiers.contains($0.key) }
        let recordsByIdentifier = Dictionary(uniqueKeysWithValues: records.map { ($0.identifier, $0) })
        let frontToBackOrder = Dictionary(uniqueKeysWithValues: records.map { ($0.identifier, $0.order) })
        let recordOwnerProcessIdentifiers = Set(records.map(\.processIdentifier))
        let recordIdentifiersByProcess = Dictionary(grouping: records, by: \.processIdentifier)
            .mapValues { Set($0.map(\.identifier)) }
        let runningProcessIdentifiers = Set(
            NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        )
        accessoryWindowScanCache.retain(processIdentifiers: runningProcessIdentifiers)
        var windows: [SwitchableWindow] = []
        var seenWindowIdentifiers: Set<CGWindowID> = []

        for app in NSWorkspace.shared.runningApplications where isEligible(
            app,
            ownsWindowServerRecord: recordOwnerProcessIdentifiers.contains(app.processIdentifier)
        ) {
            let isAccessory = app.activationPolicy == .accessory
            let appRecordIdentifiers = recordIdentifiersByProcess[app.processIdentifier] ?? []
            if
                isAccessory,
                !accessoryWindowScanCache.shouldInspect(
                    processIdentifier: app.processIdentifier,
                    windowIdentifiers: appRecordIdentifiers
                )
            {
                continue
            }

            let initialWindowCount = windows.count
            let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
            let accessibilityWindows: [AXUIElement] = copyAttribute(
                applicationElement,
                attribute: kAXWindowsAttribute as CFString,
                as: [AXUIElement].self
            ) ?? []

            for (index, element) in accessibilityWindows.enumerated() {
                guard isStandardWindow(element) else { continue }

                let minimized = copyAttribute(
                    element,
                    attribute: kAXMinimizedAttribute as CFString,
                    as: Bool.self
                ) ?? false
                guard includeMinimized || !minimized else { continue }

                let title = copyAttribute(
                    element,
                    attribute: kAXTitleAttribute as CFString,
                    as: String.self
                ) ?? ""
                let explicitIdentifier = windowIdentifier(for: element)
                let explicitRecord = explicitIdentifier.flatMap { recordsByIdentifier[$0] }
                let position = copyPoint(
                    element,
                    attribute: kAXPositionAttribute as CFString
                ) ?? explicitRecord?.bounds.origin ?? .zero
                let size = copySize(
                    element,
                    attribute: kAXSizeAttribute as CFString
                ) ?? explicitRecord?.bounds.size ?? .zero
                guard size.width >= 120, size.height >= 80 else { continue }

                let accessibilityBounds = CGRect(origin: position, size: size)
                let unmatchedRecords = records.filter {
                    !seenWindowIdentifiers.contains($0.identifier)
                }
                let matchedRecord: CGWindowRecord?
                if let explicitRecord {
                    matchedRecord = explicitRecord
                } else {
                    let descriptor = WindowMatchDescriptor(
                        processIdentifier: app.processIdentifier,
                        title: title,
                        bounds: accessibilityBounds
                    )
                    let candidateDescriptors = unmatchedRecords.map(\.matchDescriptor)
                    matchedRecord = WindowRecordMatcher.bestMatchIndex(
                        for: descriptor,
                        in: candidateDescriptors
                    ).map { unmatchedRecords[$0] }
                }
                let identifier = explicitIdentifier ?? matchedRecord?.identifier

                if let identifier {
                    seenWindowIdentifiers.insert(identifier)
                }

                let appName = app.localizedName ?? "Application"
                windows.append(
                    SwitchableWindow(
                        id: identifier.map { "\(app.processIdentifier)-\($0)" }
                            ?? "\(app.processIdentifier)-ax-\(index)-\(title)",
                        processIdentifier: app.processIdentifier,
                        windowIdentifier: identifier,
                        appName: appName,
                        appIcon: app.icon ?? fallbackAppIcon(),
                        windowTitle: title.isEmpty ? matchedRecord?.title ?? "" : title,
                        preview: identifier.flatMap(makePreview),
                        isMinimized: minimized,
                        bounds: matchedRecord?.bounds ?? accessibilityBounds,
                        accessibilityElement: element
                    )
                )
            }

            if isAccessory {
                accessoryWindowScanCache.recordResult(
                    processIdentifier: app.processIdentifier,
                    windowIdentifiers: appRecordIdentifiers,
                    foundAccessibilityWindow: windows.count > initialWindowCount
                )
            }
        }

        // Accessibility can be unavailable during first launch. Keep the switcher useful
        // enough to explain permissions by falling back to Window Server metadata.
        for record in records where !seenWindowIdentifiers.contains(record.identifier) {
            guard
                let app = NSRunningApplication(processIdentifier: record.processIdentifier),
                isEligible(app, ownsWindowServerRecord: true)
            else {
                continue
            }

            let appName = app.localizedName ?? "Application"
            windows.append(
                SwitchableWindow(
                    id: "\(record.processIdentifier)-\(record.identifier)",
                    processIdentifier: record.processIdentifier,
                    windowIdentifier: record.identifier,
                    appName: appName,
                    appIcon: app.icon ?? fallbackAppIcon(),
                    windowTitle: record.title,
                    preview: makePreview(record.identifier),
                    isMinimized: false,
                    bounds: record.bounds,
                    accessibilityElement: nil
                )
            )
        }

        let screenCaptureGranted = CGPreflightScreenCaptureAccess()
        return windows
            .filter {
                WindowPresentationFilter.shouldInclude(
                    hasPreview: $0.preview != nil,
                    screenCaptureGranted: screenCaptureGranted
                )
            }
            .sorted { lhs, rhs in
            let lhsOrder = lhs.windowIdentifier.flatMap { frontToBackOrder[$0] } ?? Int.max
            let rhsOrder = rhs.windowIdentifier.flatMap { frontToBackOrder[$0] } ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            if lhs.appName != rhs.appName {
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
            return lhs.windowTitle.localizedCaseInsensitiveCompare(rhs.windowTitle) == .orderedAscending
        }

    }

    public func activate(_ window: SwitchableWindow) {
        guard let application = NSRunningApplication(processIdentifier: window.processIdentifier) else {
            return
        }

        application.unhide()
        unminimize(window)

        if
            let windowIdentifier = window.windowIdentifier,
            WindowServerFocus.focus(
                processIdentifier: window.processIdentifier,
                windowIdentifier: windowIdentifier
            )
        {
            application.activate(options: [.activateIgnoringOtherApps])

            if
                window.accessibilityElement == nil,
                let windowIdentifier = window.windowIdentifier
            {
                window.accessibilityElement = AccessibilityWindowResolver.resolve(
                    processIdentifier: window.processIdentifier,
                    windowIdentifier: windowIdentifier
                )
            }
            raise(window)
            return
        }

        focusAndRaise(window)
        application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    public func quitApplication(owning window: SwitchableWindow) {
        NSRunningApplication(processIdentifier: window.processIdentifier)?.terminate()
    }

    private func focusAndRaise(_ window: SwitchableWindow) {
        guard let element = window.accessibilityElement else { return }

        unminimize(window)
        AXUIElementSetAttributeValue(
            element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )

        let applicationElement = AXUIElementCreateApplication(window.processIdentifier)
        AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            element
        )
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private func unminimize(_ window: SwitchableWindow) {
        guard let element = window.accessibilityElement else { return }
        AXUIElementSetAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        )
    }

    private func raise(_ window: SwitchableWindow) {
        guard let element = window.accessibilityElement else { return }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private func isEligible(
        _ application: NSRunningApplication,
        ownsWindowServerRecord: Bool
    ) -> Bool {
        return WindowApplicationEligibility.shouldInclude(
            isCurrentApplication:
                application.processIdentifier == ProcessInfo.processInfo.processIdentifier,
            isTerminated: application.isTerminated,
            kind: applicationKind(for: application.activationPolicy),
            ownsWindowServerRecord: ownsWindowServerRecord
        )
    }

    private func applicationKind(
        for activationPolicy: NSApplication.ActivationPolicy
    ) -> WindowApplicationKind {
        switch activationPolicy {
        case .regular:
            .regular
        case .accessory:
            .accessory
        case .prohibited:
            .prohibited
        @unknown default:
            .prohibited
        }
    }

    private func coreGraphicsWindowRecords() -> [CGWindowRecord] {
        guard let windowInfo = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo.enumerated().compactMap { index, info in
            guard
                let identifier = info[kCGWindowNumber as String] as? CGWindowID,
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let rawBounds = info[kCGWindowBounds as String]
            else {
                return nil
            }

            let boundsDictionary = rawBounds as! CFDictionary
            guard
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                bounds.width >= 120,
                bounds.height >= 80
            else {
                return nil
            }

            return CGWindowRecord(
                identifier: identifier,
                processIdentifier: ownerPID,
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: bounds,
                order: index
            )
        }
    }

    private func makePreview(_ identifier: CGWindowID) -> NSImage? {
        guard CGPreflightScreenCaptureAccess() else {
            return nil
        }

        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            identifier,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return previewCache[identifier]
        }
        let preview = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        previewCache[identifier] = preview
        return preview
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        let role = copyAttribute(
            element,
            attribute: kAXRoleAttribute as CFString,
            as: String.self
        )
        guard role == (kAXWindowRole as String) else { return false }

        let subrole = copyAttribute(
            element,
            attribute: kAXSubroleAttribute as CFString,
            as: String.self
        )
        return subrole == nil
            || subrole == (kAXStandardWindowSubrole as String)
            || subrole == (kAXDialogSubrole as String)
    }

    private func windowIdentifier(for element: AXUIElement) -> CGWindowID? {
        // AXWindowNumber is the Window Server ID used by Core Graphics. It is not exposed
        // as a Swift constant, but is the stable bridge needed to pair AX windows with
        // their thumbnails and front-to-back ordering.
        let attribute = "AXWindowNumber" as CFString
        if let number = copyAttribute(element, attribute: attribute, as: NSNumber.self) {
            return CGWindowID(number.uint32Value)
        }
        return nil
    }

    private func copyAttribute<T>(
        _ element: AXUIElement,
        attribute: CFString,
        as type: T.Type
    ) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func copySize(_ element: AXUIElement, attribute: CFString) -> CGSize? {
        guard let value = copyAttribute(element, attribute: attribute, as: AXValue.self) else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private func copyPoint(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        guard let value = copyAttribute(element, attribute: attribute, as: AXValue.self) else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func fallbackAppIcon() -> NSImage {
        NSImage(
            systemSymbolName: "app",
            accessibilityDescription: "Application"
        ) ?? NSImage(size: NSSize(width: 32, height: 32))
    }

}
