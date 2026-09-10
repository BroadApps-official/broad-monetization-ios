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
        if let exact = mappings[logicalPlacement] {
            return exact
        }
        guard logicalPlacement.isTokenPlacement else { return nil }
        return mappings[.tokens] ?? mappings[.custom("token")]
    }

    public func contains(
        _ logicalPlacement: PlacementID
    ) -> Bool {
        adaptyPlacement(for: logicalPlacement) != nil
    }

    /// Try the configured ID first. Only known token spelling variants are
    /// eligible for another SDK request; custom IDs are never guessed.
    func loadPaywall<Paywall: Sendable>(
        for logicalPlacement: PlacementID,
        fetch: @Sendable (AdaptyPlacementID) async -> Paywall?
    ) async -> Paywall? {
        guard let configured = adaptyPlacement(for: logicalPlacement) else { return nil }
        var candidates = [configured]
        let normalized = configured.rawValue.lowercased()
        if ["token", "tokens"].contains(normalized) {
            for value in [normalized, normalized == "token" ? "tokens" : "token"] {
                let candidate = AdaptyPlacementID(rawValue: value)
                if !candidates.contains(candidate) {
                    candidates.append(candidate)
                }
            }
        }
        for candidate in candidates {
            guard !Task.isCancelled else { return nil }
            if let paywall = await fetch(candidate) {
                return paywall
            }
        }
        return nil
    }
}
