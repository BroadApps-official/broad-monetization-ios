import Foundation

public struct EntitlementSourceEvaluation: Equatable, Sendable {
    public let source: EntitlementSource
    public let state: EntitlementState
    public let freshness: EntitlementFreshness
    public let activeValidity: EntitlementActiveValidity?
    public let validatedAt: Date?

    public var expirationDate: Date? {
        activeValidity?.expirationDate
    }

    public var isLifetime: Bool {
        activeValidity?.isLifetime == true
    }
}
