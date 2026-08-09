import Foundation

public enum EntitlementActiveValidity: Codable, Equatable, Sendable {
    // swiftlint:disable:next identifier_name
    case expires(at: Date)
    case lifetime
    case unspecified

    public var expirationDate: Date? {
        guard case let .expires(date) = self else {
            return nil
        }

        return date
    }

    public var isLifetime: Bool {
        self == .lifetime
    }

    var isStructurallyValid: Bool {
        guard case let .expires(date) = self else {
            return true
        }

        return date.timeIntervalSinceReferenceDate.isFinite
    }

    func isActive(at date: Date) -> Bool {
        guard case let .expires(expirationDate) = self else {
            return true
        }

        return expirationDate.timeIntervalSinceReferenceDate.isFinite
            && date < expirationDate
    }
}
