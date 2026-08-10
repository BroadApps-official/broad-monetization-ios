import BroadCore

enum RUBillingSafeErrors {
    static let offline = AppError(
        kind: .offline,
        userMessage: "No internet connection. Check your connection and try again.",
        diagnosticCode: "ru-billing.network-offline",
        isRetryable: true
    )

    static let timedOut = AppError(
        kind: .timeout,
        userMessage: "The connection is unstable. Please try again.",
        diagnosticCode: "ru-billing.network-timeout",
        isRetryable: true
    )

    static let notConfigured = AppError(
        kind: .unavailable,
        userMessage: "Alternative payments are not configured for this app.",
        diagnosticCode: "ru-billing.not-configured",
        isRetryable: false
    )

    static let storefrontUnavailable = AppError(
        kind: .unavailable,
        userMessage: "Payment region is temporarily unavailable.",
        diagnosticCode: "ru-billing.storefront-unavailable",
        isRetryable: true
    )

    static let catalogUnavailable = AppError(
        kind: .unavailable,
        userMessage: "Alternative payment options are temporarily unavailable.",
        diagnosticCode: "ru-billing.catalog-unavailable",
        isRetryable: true
    )

    static let checkoutUnavailable = AppError(
        kind: .unavailable,
        userMessage: "The payment page is temporarily unavailable.",
        diagnosticCode: "ru-billing.checkout-unavailable",
        isRetryable: true
    )

    static let checkoutNotEligible = AppError(
        kind: .unavailable,
        userMessage: "This payment method is not available for the current App Store account.",
        diagnosticCode: "ru-billing.checkout-not-eligible",
        isRetryable: false
    )

    static let checkoutConsentRequired = AppError(
        kind: .unavailable,
        userMessage: "Confirm the required payment terms and check the receipt email.",
        diagnosticCode: "ru-billing.checkout-consent-required",
        isRetryable: false
    )

    static let checkoutFailed = AppError(
        kind: .server,
        userMessage: "The payment could not be started. Please try again.",
        diagnosticCode: "ru-billing.checkout-failed",
        isRetryable: true
    )

    static let paymentPageOpenFailed = AppError(
        kind: .unavailable,
        userMessage: "The payment page could not be opened.",
        diagnosticCode: "ru-billing.payment-page-open-failed",
        isRetryable: true
    )

    static let paymentStatusUnavailable = AppError(
        kind: .unavailable,
        userMessage: "Payment confirmation is taking longer than expected.",
        diagnosticCode: "ru-billing.payment-status-unavailable",
        isRetryable: true
    )

    static let cancellationUnavailable = AppError(
        kind: .unavailable,
        userMessage: "Subscription management is temporarily unavailable.",
        diagnosticCode: "ru-billing.cancellation-unavailable",
        isRetryable: true
    )

    static let cancellationFailed = AppError(
        kind: .server,
        userMessage: "The subscription could not be cancelled. Please try again.",
        diagnosticCode: "ru-billing.cancellation-failed",
        isRetryable: true
    )

    static func network(
        _ failure: NetworkFailureKind,
        fallback: AppError
    ) -> AppError {
        switch failure {
        case .offline:
            offline
        case .timedOut:
            timedOut
        case .cancelled, .other:
            fallback
        }
    }
}
