import Foundation

public struct AdaptyPlacementID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmedValue.isEmpty, "Adapty placement ID must not be empty")
        precondition(trimmedValue == rawValue, "Adapty placement ID must not contain surrounding whitespace")
        self.rawValue = rawValue
    }
}

/// App-owned mapping from logical platform placements to Adapty placement IDs.
/// The platform never stores concrete dashboard IDs in its UI.
public struct AdaptyPlacementRegistry: Sendable {
    public let main: AdaptyPlacementID

    private let mappings: [PlacementID: AdaptyPlacementID]

    public init(
        main: AdaptyPlacementID,
        mappings: [PlacementID: AdaptyPlacementID] = [:]
    ) {
        precondition(
            mappings[.main].map { $0 == main } ?? true,
            "The explicit main mapping must equal the common fallback placement"
        )

        self.main = main
        self.mappings = mappings.merging([.main: main]) { current, _ in current }
    }

    public func adaptyPlacement(
        for logicalPlacement: PlacementID
    ) -> AdaptyPlacementID? {
        mappings[logicalPlacement]
    }

    public func contains(
        _ logicalPlacement: PlacementID
    ) -> Bool {
        mappings[logicalPlacement] != nil
    }
}
