import Foundation

public final class AdaptyRepositoryContext: @unchecked Sendable {
    let productRegistry: AdaptyProductRegistry
    let sdkCompositionID = AdaptySDKCompositionID()

    public init(retainedPresentationLimit: Int = 8) {
        productRegistry = AdaptyProductRegistry(
            retainedPresentationLimit: retainedPresentationLimit
        )
    }
}

/// Process-local identity of one coherent Adapty composition. Every repository
/// created by `AdaptyMonetizationFactory` shares this value through its context.
/// When a newer composition takes ownership of the global SDK, the activation
/// gate permanently rejects operations arriving from an older identity.
final class AdaptySDKCompositionID: Hashable, @unchecked Sendable {
    private static let sequenceSource = AdaptySDKCompositionSequenceSource()

    private let lock = NSLock()
    private var retired = false
    let sequence: UInt64

    init() {
        sequence = Self.sequenceSource.next()
    }

    var isRetired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return retired
    }

    /// Retirement belongs to the composition token itself. The old
    /// repositories retain this exact reference, so no bounded gate cache can
    /// accidentally let an evicted identity become current again.
    func retire() {
        lock.lock()
        retired = true
        lock.unlock()
    }

    static func == (
        lhs: AdaptySDKCompositionID,
        rhs: AdaptySDKCompositionID
    ) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

/// A process-local total order for composition ownership requests. The counter
/// is bounded memory: unlike a tombstone collection, it retains no token.
private final class AdaptySDKCompositionSequenceSource: @unchecked Sendable {
    private let lock = NSLock()
    private var nextValue: UInt64 = 1

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }

        let value = nextValue
        // Creating UInt64.max coherent Adapty compositions in one process is
        // physically unreachable. Wrapping avoids arithmetic traps while the
        // gate still fail-closes any wrapped token below its high-water mark.
        nextValue &+= 1
        return value
    }
}
