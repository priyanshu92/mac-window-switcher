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

public struct IdentifiedWindowMatchDescriptor: Equatable, Sendable {
    public let identifier: String
    public let descriptor: WindowMatchDescriptor

    public init(identifier: String, descriptor: WindowMatchDescriptor) {
        self.identifier = identifier
        self.descriptor = descriptor
    }
}

public enum FocusedWindowMatcher {
    public static func identifier(
        explicitIdentifier: String?,
        focusedWindow: WindowMatchDescriptor,
        candidates: [IdentifiedWindowMatchDescriptor]
    ) -> String? {
        if
            let explicitIdentifier,
            candidates.contains(where: { $0.identifier == explicitIdentifier })
        {
            return explicitIdentifier
        }

        return WindowRecordMatcher.bestMatchIndex(
            for: focusedWindow,
            in: candidates.map(\.descriptor)
        ).map { candidates[$0].identifier }
    }
}

public enum InitialWindowSelection {
    public static func index(windowCount: Int, movingForward: Bool) -> Int {
        guard windowCount > 1 else { return 0 }
        return movingForward ? 1 : windowCount - 1
    }
}

public struct WindowSwitchRecency: Equatable, Sendable {
    private static let missingWindowGraceScans = 4

    public private(set) var orderedWindowIdentifiers: [String] = []
    private var missingScanCounts: [String: Int] = [:]

    public init() {}

    public mutating func reconcile(
        discoveredWindowIdentifiers: [String],
        currentWindowIdentifier: String?,
        minimizedWindowIdentifiers: Set<String> = [],
        synchronizeWithDiscoveredOrder: Bool = false
    ) -> [String] {
        let discoveredIdentifiers = Set(discoveredWindowIdentifiers)

        if
            synchronizeWithDiscoveredOrder,
            let currentWindowIdentifier,
            discoveredWindowIdentifiers.first == currentWindowIdentifier
        {
            let undiscoveredIdentifiers = orderedWindowIdentifiers.filter {
                !discoveredIdentifiers.contains($0)
            }
            orderedWindowIdentifiers = discoveredWindowIdentifiers + undiscoveredIdentifiers
        }

        orderedWindowIdentifiers = orderedWindowIdentifiers.filter { identifier in
            guard !discoveredIdentifiers.contains(identifier) else {
                missingScanCounts.removeValue(forKey: identifier)
                return true
            }

            let missingScanCount = missingScanCounts[identifier, default: 0] + 1
            missingScanCounts[identifier] = missingScanCount
            if missingScanCount >= Self.missingWindowGraceScans {
                missingScanCounts.removeValue(forKey: identifier)
                return false
            }
            return true
        }

        let knownIdentifiers = Set(orderedWindowIdentifiers)
        orderedWindowIdentifiers.append(
            contentsOf: discoveredWindowIdentifiers.filter {
                !knownIdentifiers.contains($0)
            }
        )

        if
            let currentWindowIdentifier,
            discoveredIdentifiers.contains(currentWindowIdentifier)
        {
            promote(currentWindowIdentifier)
        }

        let activeWindowIdentifiers = orderedWindowIdentifiers.filter {
            !minimizedWindowIdentifiers.contains($0)
        }
        let minimizedIdentifiers = orderedWindowIdentifiers.filter {
            minimizedWindowIdentifiers.contains($0)
        }
        orderedWindowIdentifiers = activeWindowIdentifiers + minimizedIdentifiers

        return orderedWindowIdentifiers.filter(discoveredIdentifiers.contains)
    }

    public mutating func recordSelection(_ selectedWindowIdentifier: String) {
        promote(selectedWindowIdentifier)
    }

    private mutating func promote(_ identifier: String) {
        guard let index = orderedWindowIdentifiers.firstIndex(of: identifier) else {
            return
        }
        orderedWindowIdentifiers.remove(at: index)
        orderedWindowIdentifiers.insert(identifier, at: 0)
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

public enum WindowPreviewLayout {
    public static func shouldFit(
        windowBounds: CGRect,
        previewSize: CGSize
    ) -> Bool {
        guard
            windowBounds.width > 0,
            windowBounds.height > 0,
            previewSize.width > 0,
            previewSize.height > 0
        else {
            return false
        }

        let windowAspectRatio = windowBounds.width / windowBounds.height
        let previewAspectRatio = previewSize.width / previewSize.height
        let aspectRatioDifference = max(windowAspectRatio, previewAspectRatio)
            / min(windowAspectRatio, previewAspectRatio)
        return aspectRatioDifference > 1.12
    }
}

public enum WindowApplicationKind: Equatable, Sendable {
    case regular
    case accessory
    case prohibited
}

public enum WindowApplicationEligibility {
    public static func shouldInclude(
        isCurrentApplication: Bool,
        isTerminated: Bool,
        kind: WindowApplicationKind,
        ownsWindowServerRecord: Bool
    ) -> Bool {
        guard !isCurrentApplication, !isTerminated else {
            return false
        }

        switch kind {
        case .regular:
            return true
        case .accessory:
            return ownsWindowServerRecord
        case .prohibited:
            return false
        }
    }
}

public struct AccessoryWindowScanCache: Sendable {
    private var emptyWindowSignatures: [Int32: Set<UInt32>] = [:]

    public init() {}

    public mutating func shouldInspect(
        processIdentifier: Int32,
        windowIdentifiers: Set<UInt32>
    ) -> Bool {
        emptyWindowSignatures[processIdentifier] != windowIdentifiers
    }

    public mutating func recordResult(
        processIdentifier: Int32,
        windowIdentifiers: Set<UInt32>,
        foundAccessibilityWindow: Bool
    ) {
        if foundAccessibilityWindow {
            emptyWindowSignatures.removeValue(forKey: processIdentifier)
        } else {
            emptyWindowSignatures[processIdentifier] = windowIdentifiers
        }
    }

    public mutating func retain(processIdentifiers: Set<Int32>) {
        emptyWindowSignatures = emptyWindowSignatures.filter {
            processIdentifiers.contains($0.key)
        }
    }
}

public enum WindowLiveRefresh {
    public static let interval: TimeInterval = 0.5
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
