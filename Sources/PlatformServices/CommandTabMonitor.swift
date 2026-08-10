import CoreGraphics
import Foundation

public enum CommandTabGesture: Sendable {
    case cycleBackward
    case cycleForward
    case cancel
    case commit
    case quitSelected
}

nonisolated(unsafe) private var gestureHandler: (@Sendable (CommandTabGesture) -> Void)?
nonisolated(unsafe) private var eventTapReference: CFMachPort?
nonisolated(unsafe) private var gestureIsActive = false
nonisolated(unsafe) private var suppressedKeyCodes: Set<Int64> = []

private func commandTabEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTapReference {
            CGEvent.tapEnable(tap: eventTapReference, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    if type == .keyUp, suppressedKeyCodes.remove(keyCode) != nil {
        return nil
    }

    if type == .flagsChanged {
        if gestureIsActive, !event.flags.contains(.maskCommand) {
            gestureIsActive = false
            gestureHandler?(.commit)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    if keyCode == 48, event.flags.contains(.maskCommand) {
        gestureIsActive = true
        suppressedKeyCodes.insert(keyCode)
        gestureHandler?(event.flags.contains(.maskShift) ? .cycleBackward : .cycleForward)
        return nil
    }

    guard gestureIsActive else {
        return Unmanaged.passUnretained(event)
    }

    switch keyCode {
    case 53:
        gestureIsActive = false
        suppressedKeyCodes.insert(keyCode)
        gestureHandler?(.cancel)
        return nil
    case 12:
        suppressedKeyCodes.insert(keyCode)
        gestureHandler?(.quitSelected)
        return nil
    case 123:
        suppressedKeyCodes.insert(keyCode)
        gestureHandler?(.cycleBackward)
        return nil
    case 124:
        suppressedKeyCodes.insert(keyCode)
        gestureHandler?(.cycleForward)
        return nil
    default:
        return Unmanaged.passUnretained(event)
    }
}

@MainActor
public final class CommandTabMonitor {
    public enum MonitorError: LocalizedError {
        case eventTapCreationFailed

        public var errorDescription: String? {
            "Window Switcher could not monitor Command-Tab. Grant Accessibility and Input Monitoring permissions, then restart the app."
        }
    }

    public var handler: (@Sendable (CommandTabGesture) -> Void)? {
        didSet {
            gestureHandler = handler
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init() {}

    public func start() throws {
        guard eventTap == nil else { return }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: commandTabEventCallback,
            userInfo: nil
        ) else {
            throw MonitorError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        eventTapReference = tap
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        eventTapReference = nil
        gestureIsActive = false
        suppressedKeyCodes.removeAll()
    }
}
