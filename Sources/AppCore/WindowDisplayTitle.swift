import Foundation

public enum WindowDisplayTitle {
    public static func resolve(windowTitle: String, appName: String) -> String {
        let trimmedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? appName : trimmedTitle
    }
}
