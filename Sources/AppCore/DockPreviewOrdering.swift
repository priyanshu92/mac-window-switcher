import Foundation

public enum DockPreviewOrdering {
    public static func identifiers(
        discoveredIdentifiers: [String],
        previouslyDisplayedIdentifiers: [String],
        creationOrderedIdentifiers: [String]
    ) -> [String] {
        let discovered = Set(discoveredIdentifiers)
        var ordered = previouslyDisplayedIdentifiers.filter(discovered.contains)
        var known = Set(ordered)

        ordered.append(contentsOf: creationOrderedIdentifiers.filter {
            discovered.contains($0) && known.insert($0).inserted
        })
        ordered.append(contentsOf: discoveredIdentifiers.filter {
            known.insert($0).inserted
        })
        return ordered
    }
}
