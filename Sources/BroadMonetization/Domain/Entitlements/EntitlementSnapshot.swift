import Foundation

public struct EntitlementSnapshot: Equatable, Sendable {
    public let state: EntitlementState
    public let sources: [EntitlementSourceEvaluation]
    public let activeValidity: EntitlementActiveValidity?
    public let freshness: EntitlementFreshness
    public let validatedAt: Date?
    public let evaluatedAt: Date

    public var expirationDate: Date? {
        activeValidity?.expirationDate
    }

    public var isLifetime: Bool {
        activeValidity?.isLifetime == true
    }

    /// True only when the current refresh produced an authoritative active
    /// assertion. A cached or grace assertion is useful for offline access, but
    /// it must never be reported as confirmation of a new purchase or restore.
    public var isCurrentActiveConfirmed: Bool {
        sources.contains { source in
            source.state == .active && source.freshness == .refreshed
        }
    }

    /// True only when every configured source completed the current refresh and
    /// explicitly reported inactive. This is the proof required for
    /// `RestoreOutcome.nothingFound`; cached inactive values are insufficient.
    public var isCurrentInactiveConfirmed: Bool {
        !sources.isEmpty && sources.allSatisfy { source in
            source.state == .inactive && source.freshness == .refreshed
        }
    }
}
