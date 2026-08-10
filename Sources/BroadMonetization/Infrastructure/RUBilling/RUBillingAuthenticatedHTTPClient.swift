import BroadCore
import Foundation

enum RUBillingHTTPClientResult: Sendable {
    case success(RUBillingAuthenticatedResponse)
    case unauthorized
    case unavailable(NetworkFailureKind)
    case rejected
}

struct RUBillingAuthenticatedResponse: Sendable {
    let data: Data
    let authorizationProof: SubjectAuthorizationProof
}

struct RUBillingAuthenticatedHTTPClient: Sendable {
    private struct AuthorizedRequest: Sendable {
        let request: URLRequest
        let authorizationProof: SubjectAuthorizationProof
    }

    private let configuration: RUBillingHTTPConfiguration
    private let subject: EntitlementSubject
    private let authorizationProvider: any SubjectAuthorizationProviderProtocol
    private let authorizationBinding: SubjectAuthorizationBinding
    private let session: URLSession

    init(
        configuration: RUBillingHTTPConfiguration,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding
    ) {
        self.init(
            configuration: configuration,
            subject: subject,
            authorizationProvider: authorizationProvider,
            authorizationBinding: authorizationBinding,
            session: Self.makeEphemeralSession()
        )
    }

    init(
        configuration: RUBillingHTTPConfiguration,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        session: URLSession
    ) {
        precondition(
            authorizationBinding.subject == subject,
            "Authenticated HTTP binding must match the exact subject"
        )
        self.configuration = configuration
        self.subject = subject
        self.authorizationProvider = authorizationProvider
        self.authorizationBinding = authorizationBinding
        self.session = session
    }

    func send(
        path: RUBillingEndpointPath,
        method: RUBillingRequestMethod,
        timeout: TimeInterval,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async -> RUBillingHTTPClientResult {
        guard let authorizedRequest = await makeAuthorizedRequest(
            path: path,
            method: method,
            timeout: timeout,
            queryItems: queryItems,
            body: body
        ) else {
            return .unauthorized
        }
        return await execute(authorizedRequest)
    }
}

private extension RUBillingAuthenticatedHTTPClient {
    private func makeAuthorizedRequest(
        path: RUBillingEndpointPath,
        method: RUBillingRequestMethod,
        timeout: TimeInterval,
        queryItems: [URLQueryItem],
        body: Data?
    ) async -> AuthorizedRequest? {
        guard authorizationBinding.isCurrent(),
              !Task.isCancelled,
              let authorization = await authorizationProvider.authorization(for: subject),
              authorization.subject == subject,
              authorizationBinding.isCurrent(),
              let url = makeURL(path: path, queryItems: queryItems)
        else {
            return nil
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue(authorization.headerValue, forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return AuthorizedRequest(
            request: request,
            authorizationProof: SubjectAuthorizationProof(
                authorization: authorization,
                binding: authorizationBinding
            )
        )
    }

    private func execute(
        _ authorizedRequest: AuthorizedRequest
    ) async -> RUBillingHTTPClientResult {
        guard authorizedRequest.authorizationProof.isSessionCurrent,
              !Task.isCancelled
        else {
            return .unauthorized
        }
        do {
            let (bytes, response) = try await session.bytes(
                for: authorizedRequest.request
            )
            guard !Task.isCancelled,
                  let response = response as? HTTPURLResponse,
                  responseSizeIsAllowed(response.expectedContentLength)
            else {
                return .unavailable(.other)
            }
            if response.statusCode == 401 || response.statusCode == 403 {
                return .unauthorized
            }
            guard (200 ..< 300).contains(response.statusCode) else {
                return response.statusCode >= 500
                    ? .unavailable(.other)
                    : .rejected
            }

            var data = Data()
            if response.expectedContentLength > 0 {
                data.reserveCapacity(Int(response.expectedContentLength))
            }
            for try await byte in bytes {
                guard !Task.isCancelled,
                      data.count < configuration.maximumResponseSize
                else {
                    return .unavailable(.other)
                }
                data.append(byte)
            }
            guard await authorizationProvider.stillOwns(
                authorizedRequest.authorizationProof
            ) else {
                return .unauthorized
            }
            return .success(
                RUBillingAuthenticatedResponse(
                    data: data,
                    authorizationProof: authorizedRequest.authorizationProof
                )
            )
        } catch {
            return .unavailable(NetworkFailureClassifier.classify(error))
        }
    }

    func makeURL(
        path: RUBillingEndpointPath,
        queryItems: [URLQueryItem]
    ) -> URL? {
        guard var components = URLComponents(
            url: configuration.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        let basePath = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        components.percentEncodedPath = basePath + path.rawValue
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    func responseSizeIsAllowed(_ expectedContentLength: Int64) -> Bool {
        expectedContentLength == NSURLSessionTransferSizeUnknown
            || (0 ... Int64(configuration.maximumResponseSize)).contains(expectedContentLength)
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
            delegate: RUBillingNoRedirectDelegate(),
            delegateQueue: nil
        )
    }
}

private final class RUBillingNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
