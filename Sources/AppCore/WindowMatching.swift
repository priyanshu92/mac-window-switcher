import CoreGraphics
import Foundation

public struct WindowMatchDescriptor: Equatable, Sendable {
    public let processIdentifier: Int32
    public let title: String
    public let bounds: CGRect

    public init(processIdentifier: Int32, title: String, bounds: CGRect) {
        self.processIdentifier = processIdentifier
        self.title = title
        self.bounds = bounds
    }
}

public enum WindowRecordMatcher {
    public static func bestMatchIndex(
        for accessibilityWindow: WindowMatchDescriptor,
        in windowServerRecords: [WindowMatchDescriptor]
    ) -> Int? {
        let normalizedTitle = normalize(accessibilityWindow.title)

        return windowServerRecords.enumerated()
            .filter { _, candidate in
                guard candidate.processIdentifier == accessibilityWindow.processIdentifier else {
                    return false
                }

                let candidateTitle = normalize(candidate.title)
                return normalizedTitle.isEmpty
                    || candidateTitle.isEmpty
                    || candidateTitle == normalizedTitle
            }
            .min { lhs, rhs in
                score(
                    accessibilityWindow: accessibilityWindow,
                    candidate: lhs.element,
                    normalizedTitle: normalizedTitle
                ) < score(
                    accessibilityWindow: accessibilityWindow,
                    candidate: rhs.element,
                    normalizedTitle: normalizedTitle
                )
            }?
            .offset
    }

    private static func score(
        accessibilityWindow: WindowMatchDescriptor,
        candidate: WindowMatchDescriptor,
        normalizedTitle: String
    ) -> CGFloat {
        let candidateTitle = normalize(candidate.title)
        let titlePenalty: CGFloat = normalizedTitle == candidateTitle ? 0 : 10_000
        let sizeDifference =
            abs(accessibilityWindow.bounds.width - candidate.bounds.width)
            + abs(accessibilityWindow.bounds.height - candidate.bounds.height)
        let positionDifference =
            abs(accessibilityWindow.bounds.minX - candidate.bounds.minX)
            + abs(accessibilityWindow.bounds.minY - candidate.bounds.minY)
        return titlePenalty + sizeDifference + positionDifference * 0.25
    }

    private static func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum InitialWindowSelection {
    public static func index(windowCount: Int, movingForward: Bool) -> Int {
        guard windowCount > 1 else { return 0 }
        return movingForward ? 1 : windowCount - 1
    }
}

public enum WindowPresentationFilter {
    public static func shouldInclude(
        hasPreview: Bool,
        screenCaptureGranted: Bool
    ) -> Bool {
        !screenCaptureGranted || hasPreview
    }
}

public enum WindowActivationStep: Equatable, Sendable {
    case unminimize
    case frontProcessWithWindowIdentifier
    case makeWindowKey
    case activateApplication
    case resolveCrossSpaceAccessibility
    case raiseWindow
    case publicActivationFallback
}

public enum WindowActivationPlan {
    public static let fullScreenSafe: [WindowActivationStep] = [
        .unminimize,
        .frontProcessWithWindowIdentifier,
        .makeWindowKey,
        .activateApplication,
        .resolveCrossSpaceAccessibility,
        .raiseWindow,
    ]
}
