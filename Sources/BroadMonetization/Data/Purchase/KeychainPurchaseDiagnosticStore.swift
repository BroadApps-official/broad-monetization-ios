import Foundation
import Security

/// Keeps only support metadata on this device, including after app reinstall.
/// Financial intent, entitlement and token balance remain with their owners.
actor KeychainPurchaseDiagnosticStore {
    struct Record: Codable, Equatable, Sendable {
        let version: Int
        let analyticsContext: PurchaseAnalyticsContext
        let kind: PendingPurchaseDiagnostic.Kind
        let startedAt: Date
        var lastCheckedAt: Date?
        var stage: PendingPurchaseDiagnostic.Stage
        var diagnosticCode: String?

        var attemptID: MonetizationAttemptID {
            analyticsContext.attemptID
        }
    }

    enum ReadResult {
        case missing
        case value(Record)
        case unavailable
    }

    private let service: String
    private let account: String

    init(applicationIdentifier: String, kind: PendingPurchaseDiagnostic.Kind) {
        service = "dev.broadapps.monetization.purchase-diagnostic.\(applicationIdentifier)"
        account = kind.rawValue
    }

    func read() -> ReadResult {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecItemNotFound:
            return .missing
        case errSecSuccess:
            guard let data = result as? Data,
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  record.version == 1
            else { return .unavailable }
            return .value(record)
        default:
            return .unavailable
        }
    }

    @discardableResult
    func begin(
        context: PurchaseAnalyticsContext,
        kind: PendingPurchaseDiagnostic.Kind,
        startedAt: Date
    ) -> Bool {
        write(Record(
            version: 1,
            analyticsContext: context,
            kind: kind,
            startedAt: startedAt,
            lastCheckedAt: nil,
            stage: .started,
            diagnosticCode: nil
        ))
    }

    func note(
        attemptID: MonetizationAttemptID,
        stage: PendingPurchaseDiagnostic.Stage,
        diagnosticCode: String?
    ) {
        guard case var .value(record) = read(), record.attemptID == attemptID else {
            return
        }
        let now = Date()
        let safeCode = Self.safeDiagnosticCode(diagnosticCode) ?? record.diagnosticCode
        if record.stage == stage,
           record.diagnosticCode == safeCode,
           let checked = record.lastCheckedAt,
           now.timeIntervalSince(checked) < 60 {
            return
        }
        record.stage = stage
        record.diagnosticCode = safeCode
        record.lastCheckedAt = now
        _ = write(record)
    }

    func clear(attemptID: MonetizationAttemptID) {
        guard case let .value(record) = read(), record.attemptID == attemptID else {
            return
        }
        let status = SecItemDelete(baseQuery() as CFDictionary)
        _ = status == errSecSuccess || status == errSecItemNotFound
    }

    private func write(_ record: Record) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        let update = [kSecValueData as String: data]
        switch SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary) {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var item = baseQuery()
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            switch SecItemAdd(item as CFDictionary, nil) {
            case errSecSuccess:
                return true
            case errSecDuplicateItem:
                return SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
                    == errSecSuccess
            default:
                return false
            }
        default:
            return false
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    private static func safeDiagnosticCode(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.utf8.count <= 80,
              raw.utf8.allSatisfy({ byte in
                  (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
                      || (97 ... 122).contains(byte) || byte == 45 || byte == 46 || byte == 95
              })
        else { return nil }
        return raw
    }
}
