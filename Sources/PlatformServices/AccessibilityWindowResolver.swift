import ApplicationServices
import CoreGraphics
import Foundation

private typealias AXUIElementIdentifier = UInt64

@_silgen_name("_AXUIElementGetWindow")
private func privateAXWindowIdentifier(
    _ element: AXUIElement,
    _ identifier: UnsafeMutablePointer<CGWindowID>
) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func privateAXElement(
    _ token: CFData
) -> Unmanaged<AXUIElement>?

enum AccessibilityWindowResolver {
    static func resolve(
        processIdentifier: pid_t,
        windowIdentifier: CGWindowID
    ) -> AXUIElement? {
        if let liveWindow = resolveFromApplicationWindows(
            processIdentifier: processIdentifier,
            windowIdentifier: windowIdentifier
        ) {
            return liveWindow
        }

        return resolveByElementIdentifierScan(
            processIdentifier: processIdentifier,
            windowIdentifier: windowIdentifier
        )
    }

    private static func resolveFromApplicationWindows(
        processIdentifier: pid_t,
        windowIdentifier: CGWindowID
    ) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application,
                kAXWindowsAttribute as CFString,
                &value
            ) == .success,
            let windows = value as? [AXUIElement]
        else {
            return nil
        }

        return windows.first {
            identifier(of: $0) == windowIdentifier
        }
    }

    private static func resolveByElementIdentifierScan(
        processIdentifier: pid_t,
        windowIdentifier: CGWindowID
    ) -> AXUIElement? {
        // Other-Space and full-screen windows can be absent from kAXWindowsAttribute.
        // The private remote token is the only direct route from a process and AX element
        // identifier to the hidden window's accessibility object.
        var token = Data(count: 20)
        write(processIdentifier, into: &token, at: 0)
        write(Int32(0), into: &token, at: 4)
        write(Int32(0x636f636f), into: &token, at: 8)

        let deadline = ContinuousClock.now + .milliseconds(350)
        for elementIdentifier in AXUIElementIdentifier(0)..<AXUIElementIdentifier.max {
            write(elementIdentifier, into: &token, at: 12)
            if
                let element = privateAXElement(token as CFData)?.takeRetainedValue(),
                identifier(of: element) == windowIdentifier,
                role(of: element) == (kAXWindowRole as String)
            {
                return element
            }

            if ContinuousClock.now >= deadline {
                return nil
            }
        }
        return nil
    }

    static func identifier(of element: AXUIElement) -> CGWindowID? {
        var identifier = CGWindowID()
        guard privateAXWindowIdentifier(element, &identifier) == .success else {
            return nil
        }
        return identifier
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private static func write<T>(_ value: T, into data: inout Data, at offset: Int) {
        withUnsafeBytes(of: value) {
            data.replaceSubrange(offset..<(offset + $0.count), with: $0)
        }
    }
}
