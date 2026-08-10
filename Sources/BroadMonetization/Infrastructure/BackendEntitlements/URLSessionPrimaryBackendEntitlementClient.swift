import Foundation

public struct PrimaryBackendHTTPConfiguration: Sendable {
    public enum BundleValidation: Equatable, Sendable {
        case disabled
        case ifPresent(expected: String)
        case required(expected: String)
    }

    public let endpointURL: URL
    public let bundleValidation: BundleValidation
    public let requestTimeout: TimeInterval
    public let maximumResponseSize: Int

    public init(
        endpointURL: URL,
        bundleValidation: BundleValidation,
        requestTimeout: TimeInterval = 10,
        maximumResponseSize: Int = 256 * 1024
    ) {
        precondition(endpointURL.scheme?.lowercased() == "https", "Primary backend endpoint must use HTTPS")
        precondition(endpointURL.host?.isEmpty == false, "Primary backend endpoint must have a host")
        precondition(endpointURL.user == nil && endpointURL.password == nil, "Credentials must not be embedded in URL")
        precondition(endpointURL.query == nil, "Primary backend endpoint must not contain a query")
        precondition(endpointURL.fragment == nil, "Primary backend endpoint must not contain a fragment")
        precondition(requestTimeout.isFinite && requestTimeout > 0, "Request timeout must be finite and positive")
        precondition(maximumResponseSize > 0, "Maximum response size must be positive")
        switch bundleValidation {
        case .disabled:
            break
        case let .ifPresent(expected), let .required(expected):
            precondition(!expected.isEmpty, "Expected bundle identifier must not be empty")
            precondition(
                expected == expected.trimmingCharacters(in: .whitespacesAndNewlines),
                "Expected bundle identifier must not contain surrounding whitespace"
            )
        }

        self.endpointURL = endpointURL
        self.bundleValidation = bundleValidation
        self.requestTimeout = requestTimeout
        self.maximumResponseSize = maximumResponseSize
    }
}

/// Loads the BroadApps `GET /api/users/me` subscription contract without using URLSession cache.
/// Other backend schemas can implement `PrimaryBackendEntitlementClientProtocol` directly.
public struct URLSessionPrimaryBackendClient: PrimaryBackendEntitlementClientProtocol {
    private let configuration: PrimaryBackendHTTPConfiguration
    private let authorizationProvider: any SubjectAuthorizationProviderProtocol
    private let session: URLSession

    public init(
        configuration: PrimaryBackendHTTPConfiguration,
        authorizationProvider: any SubjectAuthorizationProviderProtocol
    ) {
        self.init(
            configuration: configuration,
            authorizationProvider: authorizationProvider,
            session: Self.makeEphemeralSession()
        )
    }

    init(
        configuration: PrimaryBackendHTTPConfiguration,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        session: URLSession
    ) {
        self.configuration = configuration
        self.authorizationProvider = authorizationProvider
        self.session = session
    }

    public func loadEntitlement(
        for subject: EntitlementSubject
    ) async -> PrimaryBackendEntitlementClientResult {
        guard !Task.isCancelled,
              let authorization = await authorizationProvider.authorization(for: subject),
              authorization.subject == subject
        else {
            return .unresolved
        }

        var request = URLRequest(
            url: configuration.endpointURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: configuration.requestTimeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue(authorization.headerValue, forHTTPHeaderField: "Authorization")

        do {
            guard let data = try await loadResponseData(for: request) else {
                return .unresolved
            }

            let payload = try Self.makeDecoder().decode(PrimaryBackendEntitlementResponse.self, from: data)
            guard configuration.bundleValidation.accepts(payload.appBundle) else {
                return .unresolved
            }

            return .serverValidated(
                PrimaryBackendEntitlementSnapshot(
                    subject: subject,
                    isActive: payload.subscriptionActive,
                    expiresAt: payload.subscriptionExpiresAt,
                    isLifetime: payload.subscriptionLifetime ?? false
                )
            )
        } catch {
            return .unresolved
        }
    }
}

private extension URLSessionPrimaryBackendClient {
    func loadResponseData(for request: URLRequest) async throws -> Data? {
        let (bytes, response) = try await session.bytes(for: request)
        guard !Task.isCancelled,
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              responseSizeIsAllowed(httpResponse.expectedContentLength)
        else {
            return nil
        }

        var data = Data()
        if httpResponse.expectedContentLength > 0 {
            data.reserveCapacity(Int(httpResponse.expectedContentLength))
        }
        for try await byte in bytes {
            guard !Task.isCancelled,
                  data.count < configuration.maximumResponseSize
            else {
                return nil
            }
            data.append(byte)
        }
        return data
    }

    func responseSizeIsAllowed(_ expectedContentLength: Int64) -> Bool {
        expectedContentLength == NSURLSessionTransferSizeUnknown
            || (0 ... Int64(configuration.maximumResponseSize)).contains(expectedContentLength)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = PrimaryBackendDateParser.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid subscription expiration date"
                )
            }
            return date
        }
        return decoder
    }

    static func makeEphemeralSession() -> URLSession {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = nil
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.urlCredentialStorage = nil
        sessionConfiguration.waitsForConnectivity = false
        return URLSession(
            configuration: sessionConfiguration,
            delegate: PrimaryBackendNoRedirectDelegate(),
            delegateQueue: nil
        )
    }
}

private struct PrimaryBackendEntitlementResponse: Decodable {
    let appBundle: String?
    let subscriptionActive: Bool
    let subscriptionExpiresAt: Date?
    let subscriptionLifetime: Bool?

    enum CodingKeys: String, CodingKey {
        case appBundle = "app_bundle"
        case subscriptionActive = "subscription_active"
        case subscriptionExpiresAt = "subscription_expires_at"
        case subscriptionLifetime = "subscription_lifetime"
    }
}

private final class PrimaryBackendNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum PrimaryBackendDateParser {
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        let microsecondsFormatter = DateFormatter()
        microsecondsFormatter.locale = Locale(identifier: "en_US_POSIX")
        microsecondsFormatter.calendar = Calendar(identifier: .gregorian)
        microsecondsFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        microsecondsFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        if let date = microsecondsFormatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private extension PrimaryBackendHTTPConfiguration.BundleValidation {
    func accepts(_ receivedBundleIdentifier: String?) -> Bool {
        switch self {
        case .disabled:
            true
        case let .ifPresent(expected):
            receivedBundleIdentifier.map { $0 == expected } ?? true
        case let .required(expected):
            receivedBundleIdentifier == expected
        }
    }
}
