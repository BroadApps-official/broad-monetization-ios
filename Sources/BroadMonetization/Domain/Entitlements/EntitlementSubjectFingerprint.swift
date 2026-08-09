import Foundation

public struct EntitlementSubjectFingerprint: Equatable, Hashable, Sendable {
    private static let requiredByteCount = 32

    let storageComponent: String

    public init(bytes: Data) {
        precondition(
            bytes.count == Self.requiredByteCount,
            "Entitlement subject fingerprint must contain exactly 32 bytes"
        )

        storageComponent = bytes.map(Self.hexByte).joined()
    }

    private static func hexByte(_ byte: UInt8) -> String {
        let digits = Array("0123456789abcdef".utf8)
        let high = digits[Int(byte >> 4)]
        let low = digits[Int(byte & 0x0F)]
        return String(bytes: [high, low], encoding: .utf8) ?? ""
    }
}
