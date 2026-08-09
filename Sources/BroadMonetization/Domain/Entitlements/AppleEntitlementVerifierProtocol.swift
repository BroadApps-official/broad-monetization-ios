public protocol AppleEntitlementVerifierProtocol: Sendable {
    /// Returns only evidence qualified for the current subject and refresh attempt.
    /// Hidden SDK cache without trustworthy provenance must return `unresolved`.
    func verifyEntitlement(
        for subject: EntitlementSubject
    ) async -> EntitlementSourceResolution
}
