public struct EntitlementCacheScope: Equatable, Hashable, Sendable {
    public let source: EntitlementSource
    public let subject: EntitlementSubject
    let partition: String?
    let storagePartition: String?

    public init(
        source: EntitlementSource,
        subject: EntitlementSubject
    ) {
        self.init(
            source: source,
            subject: subject,
            partition: nil,
            storagePartition: nil
        )
    }

    init(
        source: EntitlementSource,
        subject: EntitlementSubject,
        partition: String?,
        storagePartition: String?
    ) {
        precondition(
            (partition == nil) == (storagePartition == nil),
            "Entitlement cache partitions must be both present or both absent"
        )
        self.source = source
        self.subject = subject
        self.partition = partition
        self.storagePartition = storagePartition
    }
}
