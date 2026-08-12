import AppCore
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public struct DockApplicationTarget: Equatable, Sendable {
    public let bundleURL: URL

    public init(bundleURL: URL) {
        self.bundleURL = bundleURL
    }
}

public enum DockInteractionEvent: Equatable, Sendable {
    case hover(DockApplicationTarget?)
    case click(DockApplicationTarget)
    case contextMenu
}

nonisolated(unsafe) private var dockInteractionHandler:
    (@Sendable (DockInteractionEvent) -> Void)?
nonisolated(unsafe) private var dockEventTapReference: CFMachPort?
nonisolated(unsafe) private var suppressDockMouseUp = false
nonisolated(unsafe) private var dockContextMenuActive = false

private func dockEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let dockEventTapReference {
            CGEvent.tapEnable(tap: dockEventTapReference, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .leftMouseUp, suppressDockMouseUp {
        suppressDockMouseUp = false
        return nil
    }

    let button: DockPointerButton
    switch type {
    case .leftMouseDown:
        button = .primary
    case .rightMouseDown:
        button = .secondary
    default:
        return Unmanaged.passUnretained(event)
    }

    guard
        let target = DockAccessibilityResolver.applicationTarget(at: event.location)
    else {
        return Unmanaged.passUnretained(event)
    }

    switch DockPointerInteraction.action(
        button: button,
        controlPressed: event.flags.contains(.maskControl),
        contextMenuActive: dockContextMenuActive
    ) {
    case .handlePrimaryClick:
        // Suppress both halves of the native Dock click so it cannot activate an
        // arbitrary app window before the app-specific picker handles the click.
        suppressDockMouseUp = true
        dockInteractionHandler?(.click(target))
        return nil
    case .dismissForContextMenu:
        dockContextMenuActive = true
        dockInteractionHandler?(.contextMenu)
        return Unmanaged.passUnretained(event)
    case .ignore:
        return Unmanaged.passUnretained(event)
    }
}

private enum DockAccessibilityResolver {
    // Dock app icons expose the AXApplicationDockItem subrole and an AXURL
    // pointing to the application bundle:
    // https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition
    private static let applicationDockItemSubrole = "AXApplicationDockItem"

    static func applicationTarget(at point: CGPoint) -> DockApplicationTarget? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        guard
            AXUIElementCopyElementAtPosition(
                systemWideElement,
                Float(point.x),
                Float(point.y),
                &hitElement
            ) == .success,
            let hitElement
        else {
            return nil
        }

        var candidate: AXUIElement? = hitElement
        for _ in 0..<6 {
            guard let element = candidate else { break }
            let subrole = copyAttribute(
                element,
                attribute: kAXSubroleAttribute as CFString,
                as: String.self
            )
            if
                subrole == applicationDockItemSubrole,
                let bundleURL = copyAttribute(
                    element,
                    attribute: kAXURLAttribute as CFString,
                    as: URL.self
                )
            {
                return DockApplicationTarget(bundleURL: bundleURL.standardizedFileURL)
            }

            candidate = copyAttribute(
                element,
                attribute: kAXParentAttribute as CFString,
                as: AXUIElement.self
            )
        }
        return nil
    }

    private static func copyAttribute<T>(
        _ element: AXUIElement,
        attribute: CFString,
        as type: T.Type
    ) -> T? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value
        else {
            return nil
        }
        return value as? T
    }
}

@MainActor
public final class DockInteractionMonitor {
    public enum MonitorError: LocalizedError {
        case eventTapCreationFailed

        public var errorDescription: String? {
            "Window Switcher could not monitor Dock clicks. Grant Accessibility and Input Monitoring permissions, then restart the app."
        }
    }

    public var handler: (@Sendable (DockInteractionEvent) -> Void)? {
        didSet {
            dockInteractionHandler = handler
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mouseMovedMonitor: Any?
    private var hoverResolutionTask: Task<Void, Never>?
    private var suppressHoverForContextMenu = false

    public init() {}

    public func start() throws {
        guard eventTap == nil else { return }

        let eventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: dockEventCallback,
            userInfo: nil
        ) else {
            throw MonitorError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        dockEventTapReference = tap

        mouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .mouseMoved
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pointerDidMove()
            }
        }
    }

    public func stop() {
        hoverResolutionTask?.cancel()
        hoverResolutionTask = nil
        if let mouseMovedMonitor {
            NSEvent.removeMonitor(mouseMovedMonitor)
        }
        mouseMovedMonitor = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        dockEventTapReference = nil
        suppressDockMouseUp = false
        dockContextMenuActive = false
        suppressHoverForContextMenu = false
        dockInteractionHandler?(.hover(nil))
    }

    private func pointerDidMove() {
        hoverResolutionTask?.cancel()
        hoverResolutionTask = nil

        let pointerLocation = NSEvent.mouseLocation
        if suppressHoverForContextMenu {
            if !isNearPossibleDockEdge(pointerLocation) {
                suppressHoverForContextMenu = false
                dockContextMenuActive = false
            }
            dockInteractionHandler?(.hover(nil))
            return
        }
        guard isNearPossibleDockEdge(pointerLocation) else {
            dockInteractionHandler?(.hover(nil))
            return
        }

        hoverResolutionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(
                    DockPreviewTiming.hoverDetectionDebounce * 1_000_000_000
                )
            )
            guard !Task.isCancelled, let self else { return }
            let target = CGEvent(source: nil).flatMap {
                DockAccessibilityResolver.applicationTarget(at: $0.location)
            }
            dockInteractionHandler?(.hover(target))
            hoverResolutionTask = nil
        }
    }

    public func suppressHoverUntilPointerLeavesDock() {
        hoverResolutionTask?.cancel()
        hoverResolutionTask = nil
        suppressHoverForContextMenu = true
        dockContextMenuActive = true
        dockInteractionHandler?(.hover(nil))
    }

    private func isNearPossibleDockEdge(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return false
        }

        let frame = screen.frame
        // AX hit-testing is deferred until the pointer settles near an edge.
        // The Dock can only be placed on the bottom, left, or right screen edge.
        let edgeDistance: CGFloat = 180
        return point.y - frame.minY <= edgeDistance
            || point.x - frame.minX <= edgeDistance
            || frame.maxX - point.x <= edgeDistance
    }
}
