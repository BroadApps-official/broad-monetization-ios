import Foundation

enum RUExperimentHTTPProbe {
    static func run() async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RUProbeURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let authorization = SubjectAuthorizationSession()
        let path = RUBillingEndpointPath(rawValue: "/fixture-unused")
        let client = RUBillingAuthenticatedHTTPClient(
            configuration: RUBillingHTTPConfiguration(
                baseURL: URL(string: "https://fixture.invalid")!, applicationID: "fixture", appBundleIdentifier: "fixture.example",
                endpoints: .init(catalog: path, checkout: path, paymentStatus: path, entitlementStatus: path, cancellation: path)
            ), subject: .anonymous, authorizationProvider: RUProbeAuthorization(),
            authorizationBinding: authorization.begin(for: .anonymous), session: session
        )
        let repository = URLSessionRUExperimentRepository(client: client, configuration: .broadApps)
        let request = RUExperimentEvent(
            metadata: RUExperimentMetadata(experimentCode: "fixture", segmentCode: "a")!,
            placement: "fixture-main"
        )!
        RUProbeURLProtocol.state.configure(
            status: 200,
            body: #"{"segment":{"code":"b","isControl":true},"requestedSegmentMatches":false,"created":false}"#
        )
        guard case let .assigned(assigned) = await repository.assign(request) else { fatalError("Expected stored assignment") }
        check(assigned.metadata.segmentCode == "b" && !assigned.requestedSegmentMatches)
        let captured = RUProbeURLProtocol.state.requests.last!
        check(captured.httpMethod == "POST")
        check(captured.url?.path == "/v1/billing/cloudpayments/experiments/assign")
        check(captured.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        let body = try JSONSerialization.jsonObject(with: RUProbeURLProtocol.state.bodies.last!) as! [String: String]
        check(body == ["experimentCode": "fixture", "segmentCode": "a", "placement": "fixture-main"])
        RUProbeURLProtocol.state.configure(status: 200, body: #"{"logged":true}"#)
        await check(repository.paywallShown(RUExperimentEvent(metadata: assigned.metadata, placement: request.placement)!) == .logged)
        check(RUProbeURLProtocol.state.requests.last!.url?.path == "/v1/billing/cloudpayments/experiments/paywall-shown")
        for status in [401, 403, 429, 500, 503] {
            let count = RUProbeURLProtocol.state.requests.count
            RUProbeURLProtocol.state.configure(status: status, body: "{}")
            let result = await repository.assign(request)
            switch result {
            case .assigned: fatalError("HTTP failure must not assign")
            case .unauthorized: check(status == 401 || status == 403)
            case .unavailable: check(status >= 500)
            case .rejected: check(status == 429)
            }
            check(RUProbeURLProtocol.state.requests.count == count + 1)
        }
        for malformed in [
            #"{"segment":{"code":"b","isControl":true},"requestedSegmentMatches":true,"created":false}"#,
            #"{"segment":{"code":1,"isControl":true},"requestedSegmentMatches":false,"created":false}"#,
            "{}"
        ] {
            RUProbeURLProtocol.state.configure(status: 200, body: malformed)
            guard case .rejected = await repository.assign(request) else { fatalError("Malformed assignment accepted") }
        }
        RUProbeURLProtocol.state.configure(status: 200, body: #"{"logged":false}"#)
        await check(repository.paywallShown(request) == .rejected)
        let accountRepository = URLSessionRUAccountPolicyRepository(
            configuration: .init(
                baseURL: URL(string: "https://fixture.invalid")!, applicationID: "fixture", appBundleIdentifier: "fixture.example",
                endpoints: .init(
                    catalog: path,
                    checkout: path,
                    entitlementStatus: .init(rawValue: "/v1/policy/effective"),
                    cancellation: path
                )
            ), subject: .anonymous, client: client
        )
        RUProbeURLProtocol.state.configure(status: 200, body: #"{"isSubscribed":true,"plan":"monthly","creditsBalance":50}"#)
        guard case let .loaded(policy) = await accountRepository.loadPolicy(for: .anonymous) else { fatalError("Expected account policy") }
        check(policy.isSubscribed && policy.creditsBalance == 50)
        let accountRequest = RUProbeURLProtocol.state.requests.last!
        check(accountRequest.httpMethod == "GET" && accountRequest.url?.path == "/v1/policy/effective")
        check(accountRequest.url?.query == nil && accountRequest.httpBody == nil)
        check(accountRequest.cachePolicy == .reloadIgnoringLocalCacheData)
        for status in [401, 403, 500] {
            RUProbeURLProtocol.state.configure(status: status, body: "{}")
            guard case .unavailable = await accountRepository.loadPolicy(for: .anonymous) else { fatalError("Stale account accepted") }
        }
        let count = RUProbeURLProtocol.state.requests.count
        authorization.invalidate()
        guard case .unavailable = await accountRepository.loadPolicy(for: .anonymous) else { fatalError("Revoked account accepted") }
        guard case .unauthorized = await repository.assign(request) else { fatalError("Revoked session accepted") }
        check(RUProbeURLProtocol.state.requests.count == count)

        let decoder = FlatRUCatalogResponseDecoder(supportedMethods: [.card])
        for key in ["isDefault", "default", "is_default"] {
            let json = "{\"products\":[{\"productId\":\"fixture\",\"kind\":\"subscription\",\"\(key)\":true},{\"productId\":\"fixture\",\"isDefault\":\"bad\"}]}"
            let catalog = try decoder.decodeCatalog(from: Data(json.utf8), fetchedAt: Date())
            check(catalog.products.count == 2 && catalog.products[0].isDefault && !catalog.products[1].isDefault)
        }
    }
}

struct RUProbeAuthorization: SubjectAuthorizationProviderProtocol {
    func authorization(for subject: EntitlementSubject) async -> SubjectBoundAuthorization? {
        SubjectBoundAuthorization(subject: subject, bearerToken: "fixture-token")
    }
}

final class RUProbeURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = RUProbeHTTPState()
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = Self.state.respond(to: request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: response.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
        )!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RUProbeHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var body = Data()
    private var captured: [URLRequest] = []
    private var capturedBodies: [Data] = []
    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return captured
    }

    var bodies: [Data] {
        lock.lock(); defer { lock.unlock() }; return capturedBodies
    }

    func configure(status: Int, body: String) {
        lock.lock(); defer { lock.unlock() }
        self.status = status
        self.body = Data(body.utf8)
    }

    func respond(to request: URLRequest) -> (Int, Data) {
        var requestBody = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 {
                    break
                }
                requestBody.append(contentsOf: buffer.prefix(count))
            }
        }
        lock.lock(); defer { lock.unlock() }
        captured.append(request)
        capturedBodies.append(requestBody)
        return (status, body)
    }
}

func check(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(condition, "RU experiment contract failed", file: file, line: line)
}
