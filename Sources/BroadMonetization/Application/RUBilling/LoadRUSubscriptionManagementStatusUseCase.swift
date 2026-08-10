import BroadCore
import Foundation

public struct RUSubscriptionManagementStatus: Equatable, Sendable {
    public let subscriptionID: RUSubscriptionID?
    public let planName: String?
    public let isActive: Bool
    public let expiresAt: Date?
    public let isLifetime: Bool
    public let isAutoRenewalCancelled: Bool

    public init(
        subscriptionID: RUSubscriptionID?,
        planName: String?,
        isActive: Bool,
        expiresAt: Date?,
        isLifetime: Bool,
        isAutoRenewalCancelled: Bool
    ) {
        precondition(
            expiresAt?.timeIntervalSinceReferenceDate.isFinite != false,
            "RU subscription expiration must be finite"
        )
        self.subscriptionID = subscriptionID
        self.planName = planName
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.isLifetime = isLifetime
        self.isAutoRenewalCancelled = isAutoRenewalCancelled
    }
}

public enum RUSubscriptionManagementLoadOutcome: Equatable, Sendable {
    case loaded(RUSubscriptionManagementStatus)
    case unavailable(AppError)
}

public struct LoadRUSubscriptionStatusUseCase:
    LoadRUSubscriptionStatusUseCaseProtocol {
    private let client: any RUBillingEntitlementClientProtocol
    private let subject: EntitlementSubject
    private let authorizationBinding: SubjectAuthorizationBinding

    public init(
        client: any RUBillingEntitlementClientProtocol,
        subject: EntitlementSubject,
        authorizationBinding: SubjectAuthorizationBinding
    ) {
        precondition(
            authorizationBinding.subject == subject,
            "RU management authorization must match the exact subject"
        )
        self.client = client
        self.subject = subject
        self.authorizationBinding = authorizationBinding
    }

    public func callAsFunction() async -> RUSubscriptionManagementLoadOutcome {
        guard authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.cancellationUnavailable)
        }
        switch await client.loadEntitlement(for: subject) {
        case let .serverValidated(record)
            where authorizationBinding.isCurrent() && record.subject == subject:
            return .loaded(
                RUSubscriptionManagementStatus(
                    subscriptionID: record.subscriptionID,
                    planName: record.planName,
                    isActive: record.isActive,
                    expiresAt: record.expiresAt,
                    isLifetime: record.isLifetime,
                    isAutoRenewalCancelled: record.isAutoRenewalCancelled
                )
            )
        case .serverValidated, .unresolved:
            return .unavailable(RUBillingSafeErrors.cancellationUnavailable)
        }
    }
}
