public struct EntitlementSubject: Equatable, Hashable, Sendable {
    public static let anonymous = EntitlementSubject(
        cacheKeyComponent: "anonymous"
    )

    let cacheKeyComponent: String

    public static func fingerprinted(
        _ fingerprint: EntitlementSubjectFingerprint
    ) -> EntitlementSubject {
        EntitlementSubject(
            cacheKeyComponent: "subject-\(fingerprint.storageComponent)"
        )
    }
}
