public protocol EntitlementSourceRepositoryProtocol: Sendable {
    /// Performs an authoritative check for exactly this subject.
    /// Transport errors, unverified transactions and unqualified SDK cache map to `unresolved`.
    func resolveEntitlement(
        for subject: EntitlementSubject
    ) async -> EntitlementSourceResolution
}
