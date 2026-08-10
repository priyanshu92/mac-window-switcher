import Carbon
import CoreGraphics
import Darwin
import Foundation

private enum WindowServerFocusMode {
    static let userGenerated: UInt32 = 0x200
}

@_silgen_name("GetProcessForPID")
private func legacyGetProcessForPID(
    _ processIdentifier: pid_t,
    _ process: UnsafeMutablePointer<ProcessSerialNumber>
) -> OSStatus

enum WindowServerFocus {
    private typealias SetFrontProcessFunction = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>,
        CGWindowID,
        UInt32
    ) -> CGError
    private typealias PostEventFunction = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>,
        UnsafeMutablePointer<UInt8>
    ) -> CGError

    static func focus(
        processIdentifier: pid_t,
        windowIdentifier: CGWindowID
    ) -> Bool {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL
        ) else {
            return false
        }
        defer { dlclose(handle) }

        guard
            let setFrontSymbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions"),
            let postEventSymbol = dlsym(handle, "SLPSPostEventRecordTo")
        else {
            return false
        }
        let setFrontProcess = unsafeBitCast(
            setFrontSymbol,
            to: SetFrontProcessFunction.self
        )
        let postEvent = unsafeBitCast(
            postEventSymbol,
            to: PostEventFunction.self
        )

        var process = ProcessSerialNumber()
        let processResult = legacyGetProcessForPID(processIdentifier, &process)
        guard processResult == noErr else {
            return false
        }

        let frontResult = setFrontProcess(
            &process,
            windowIdentifier,
            WindowServerFocusMode.userGenerated
        )
        guard frontResult == .success else {
            return false
        }

        let keyResult = makeKey(
            process: &process,
            windowIdentifier: windowIdentifier,
            postEvent: postEvent
        )
        return keyResult == .success
    }

    private static func makeKey(
        process: inout ProcessSerialNumber,
        windowIdentifier: CGWindowID,
        postEvent: PostEventFunction
    ) -> CGError {
        // WindowServer has no public API for making a specific foreign window key.
        // A targeted mouse-down event performs that key-window transition without a
        // corresponding mouse-up, so no control in the destination window is activated.
        let recordSize = 0x100
        let declaredLengthOffset = 0x04
        let eventTypeOffset = 0x08
        let windowLocationOffset = 0x20
        let unknownFlagOffset = 0x3a
        let windowIdentifierOffset = 0x3c

        var record = [UInt8](repeating: 0, count: recordSize)
        record[declaredLengthOffset] = 0xf8
        record[eventTypeOffset] = UInt8(CGEventType.leftMouseDown.rawValue)
        record[unknownFlagOffset] = 0x10

        var identifier = windowIdentifier
        // The event is routed by window ID. Keeping its nominal location far outside
        // the window prevents WindowServer from resolving it onto visible content.
        var offContentPoint = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &identifier) {
            record.replaceSubrange(
                windowIdentifierOffset..<(windowIdentifierOffset + $0.count),
                with: $0
            )
        }
        withUnsafeBytes(of: &offContentPoint) {
            record.replaceSubrange(
                windowLocationOffset..<(windowLocationOffset + $0.count),
                with: $0
            )
        }

        return record.withUnsafeMutableBufferPointer {
            postEvent(&process, $0.baseAddress!)
        }
    }

}
