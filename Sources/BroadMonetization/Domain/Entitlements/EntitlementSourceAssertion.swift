import Foundation

public struct EntitlementSourceAssertion: Codable, Equatable, Sendable {
    public let source: EntitlementSource
    public let state: ResolvedEntitlementState
    public let validatedAt: Date
    public let freshUntil: Date
    public let activeGraceUntil: Date

    public init(
        source: EntitlementSource,
        state: ResolvedEntitlementState,
        validatedAt: Date,
        freshUntil: Date,
        activeGraceUntil: Date
    ) {
        precondition(
            Self.hasValidStructure(
                state: state,
                validatedAt: validatedAt,
                freshUntil: freshUntil,
                activeGraceUntil: activeGraceUntil
            ),
            "Entitlement assertion dates and validity must be consistent"
        )

        self.source = source
        self.state = state
        self.validatedAt = validatedAt
        self.freshUntil = freshUntil
        self.activeGraceUntil = activeGraceUntil
    }

    var hasValidStructure: Bool {
        Self.hasValidStructure(
            state: state,
            validatedAt: validatedAt,
            freshUntil: freshUntil,
            activeGraceUntil: activeGraceUntil
        )
    }

    private static func hasValidStructure(
        state: ResolvedEntitlementState,
        validatedAt: Date,
        freshUntil: Date,
        activeGraceUntil: Date
    ) -> Bool {
        let timestamps = [
            validatedAt.timeIntervalSinceReferenceDate,
            freshUntil.timeIntervalSinceReferenceDate,
            activeGraceUntil.timeIntervalSinceReferenceDate
        ]
        guard timestamps.allSatisfy(\.isFinite) else {
            return false
        }

        guard freshUntil >= validatedAt, activeGraceUntil >= freshUntil else {
            return false
        }

        guard case let .active(validity) = state else {
            return true
        }

        return validity.isStructurallyValid
    }
}
