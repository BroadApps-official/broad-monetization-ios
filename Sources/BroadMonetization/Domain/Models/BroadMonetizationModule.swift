import BroadCore

public struct BroadMonetizationModule: Equatable, Sendable {
    public let identifier: String
    public let coreIdentifier: String
    public let isAdaptyLinked: Bool

    public init(
        identifier: String = "BroadMonetization",
        coreIdentifier: String,
        isAdaptyLinked: Bool
    ) {
        self.identifier = identifier
        self.coreIdentifier = coreIdentifier
        self.isAdaptyLinked = isAdaptyLinked
    }
}
