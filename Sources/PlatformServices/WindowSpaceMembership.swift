import CoreGraphics
import Foundation

private typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
private func mainWindowServerConnection() -> CGSConnectionID

@_silgen_name("CGSCopySpacesForWindows")
private func copySpacesForWindows(
    _ connection: CGSConnectionID,
    _ mask: Int,
    _ windowIdentifiers: CFArray
) -> CFArray

enum WindowSpaceMembership {
    static func contains(_ windowIdentifier: CGWindowID) -> Bool {
        // Window Server can retain closed surfaces in CGWindowListCopyWindowInfo.
        // Live off-Space and full-screen windows still have a Space assignment,
        // while retained closed surfaces return an empty list.
        // CGSCopySpacesForWindows is private but is also used by AltTab:
        // https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift
        let identifiers = [NSNumber(value: windowIdentifier)] as CFArray
        let allSpacesMask = 7
        return CFArrayGetCount(
            copySpacesForWindows(
                mainWindowServerConnection(),
                allSpacesMask,
                identifiers
            )
        ) > 0
    }
}
