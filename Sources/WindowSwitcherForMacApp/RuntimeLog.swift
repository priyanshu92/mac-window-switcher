import Foundation

func switcherLog(_ message: String) {
    FileHandle.standardError.write(Data("[WindowSwitcher] \(message)\n".utf8))
}
