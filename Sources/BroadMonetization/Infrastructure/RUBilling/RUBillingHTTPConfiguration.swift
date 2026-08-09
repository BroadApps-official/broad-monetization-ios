import Foundation

public struct RUBillingEndpointPath: RawRepresentable, Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.hasPrefix("/"), "RU billing endpoint path must start with a slash")
        precondition(!rawValue.hasPrefix("//"), "RU billing endpoint path must be relative to the configured host")
        precondition(
            rawValue.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            },
            "RU billing endpoint path must not contain control characters"
        )

        let components = URLComponents(string: rawValue)
        precondition(
            components?.scheme == nil
                && components?.host == nil
                && components?.query == nil
                && components?.fragment == nil,
            "RU billing endpoint path must not contain an origin, query or fragment"
        )
        precondition(
            !rawValue.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
            "RU billing endpoint path must not contain traversal components"
        )

        self.rawValue = rawValue
    }
}

public struct RUBillingEndpointConfiguration: Equatable, Sendable {
    public let catalog: RUBillingEndpointPath
    public let checkout: RUBillingEndpointPath
    public let paymentStatus: RUBillingEndpointPath
    public let entitlementStatus: RUBillingEndpointPath
    public let cancellation: RUBillingEndpointPath
    public let legacyCancellation: RUBillingEndpointPath?

    public init(
        catalog: RUBillingEndpointPath,
        checkout: RUBillingEndpointPath,
        paymentStatus: RUBillingEndpointPath,
        entitlementStatus: RUBillingEndpointPath,
        cancellation: RUBillingEndpointPath,
        legacyCancellation: RUBillingEndpointPath? = nil
    ) {
        self.catalog = catalog
        self.checkout = checkout
        self.paymentStatus = paymentStatus
        self.entitlementStatus = entitlementStatus
        self.cancellation = cancellation
        self.legacyCancellation = legacyCancellation
    }
}

public struct RUBillingRequestTimeouts: Equatable, Sendable {
    public let catalog: TimeInterval
    public let checkout: TimeInterval
    public let paymentStatus: TimeInterval
    public let entitlementStatus: TimeInterval
    public let cancellation: TimeInterval

    public init(
        catalog: TimeInterval = 15,
        checkout: TimeInterval = 15,
        paymentStatus: TimeInterval = 10,
        entitlementStatus: TimeInterval = 10,
        cancellation: TimeInterval = 15
    ) {
        let values = [catalog, checkout, paymentStatus, entitlementStatus, cancellation]
        precondition(
            values.allSatisfy { $0.isFinite && $0 > 0 },
            "RU billing request timeouts must be finite and positive"
        )

        self.catalog = catalog
        self.checkout = checkout
        self.paymentStatus = paymentStatus
        self.entitlementStatus = entitlementStatus
        self.cancellation = cancellation
    }
}

public struct RUBillingHTTPConfiguration: Sendable {
    public static let maximumAllowedResponseSize = 8 * 1024 * 1024

    public let baseURL: URL
    public let applicationID: String
    public let appBundleIdentifier: String
    public let endpoints: RUBillingEndpointConfiguration
    public let requestTimeouts: RUBillingRequestTimeouts
    public let maximumResponseSize: Int
    public let allowsLegacyCancellationFallback: Bool

    public init(
        baseURL: URL,
        applicationID: String,
        appBundleIdentifier: String,
        endpoints: RUBillingEndpointConfiguration,
        requestTimeouts: RUBillingRequestTimeouts = RUBillingRequestTimeouts(),
        maximumResponseSize: Int = 512 * 1024,
        allowsLegacyCancellationFallback: Bool = false
    ) {
        precondition(baseURL.scheme?.lowercased() == "https", "RU billing base URL must use HTTPS")
        precondition(baseURL.host?.isEmpty == false, "RU billing base URL must have a host")
        precondition(baseURL.user == nil && baseURL.password == nil, "Credentials must not be embedded in RU billing URL")
        precondition(baseURL.query == nil && baseURL.fragment == nil, "RU billing base URL must not contain query or fragment")
        precondition(!applicationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Application ID must not be empty")
        precondition(applicationID.utf8.count <= 1024, "Application ID is too long")
        precondition(
            applicationID == applicationID.trimmingCharacters(in: .whitespacesAndNewlines),
            "Application ID must not contain surrounding whitespace"
        )
        precondition(!appBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Bundle ID must not be empty")
        precondition(appBundleIdentifier.utf8.count <= 1024, "Bundle ID is too long")
        precondition(
            appBundleIdentifier == appBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            "Bundle ID must not contain surrounding whitespace"
        )
        precondition(
            (1 ... Self.maximumAllowedResponseSize).contains(maximumResponseSize),
            "Maximum RU billing response size is outside the safe range"
        )
        precondition(
            !allowsLegacyCancellationFallback || endpoints.legacyCancellation != nil,
            "Legacy cancellation fallback requires an explicit endpoint"
        )

        self.baseURL = baseURL
        self.applicationID = applicationID
        self.appBundleIdentifier = appBundleIdentifier
        self.endpoints = endpoints
        self.requestTimeouts = requestTimeouts
        self.maximumResponseSize = maximumResponseSize
        self.allowsLegacyCancellationFallback = allowsLegacyCancellationFallback
    }
}
