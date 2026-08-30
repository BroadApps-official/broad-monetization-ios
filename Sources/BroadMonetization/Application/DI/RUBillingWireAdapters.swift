public struct RUCatalogWireAdapters: Sendable {
    public let requestEncoder: any RUCatalogRequestEncoderProtocol
    public let responseDecoder: any RUCatalogResponseDecoderProtocol

    public init(
        requestEncoder: any RUCatalogRequestEncoderProtocol,
        responseDecoder: any RUCatalogResponseDecoderProtocol
    ) {
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
    }
}

public struct RUCheckoutWireAdapters: Sendable {
    public let requestEncoder: any RUCheckoutRequestEncoderProtocol
    public let responseDecoder: any RUCheckoutResponseDecoderProtocol

    public init(
        requestEncoder: any RUCheckoutRequestEncoderProtocol,
        responseDecoder: any RUCheckoutResponseDecoderProtocol
    ) {
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
    }
}

public struct RUPaymentStatusWireAdapters: Sendable {
    public let requestEncoder: any RUPaymentStatusRequestEncoderProtocol
    public let responseDecoder: any RUPaymentStatusResponseDecoderProtocol

    public init(
        requestEncoder: any RUPaymentStatusRequestEncoderProtocol,
        responseDecoder: any RUPaymentStatusResponseDecoderProtocol
    ) {
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
    }
}

public struct RUCancellationWireAdapters: Sendable {
    public let requestEncoder: any RUCancellationRequestEncoderProtocol
    public let responseDecoder: any RUCancellationResponseDecoderProtocol

    public init(
        requestEncoder: any RUCancellationRequestEncoderProtocol,
        responseDecoder: any RUCancellationResponseDecoderProtocol
    ) {
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
    }
}

public struct RUEntitlementWireAdapters: Sendable {
    public let requestEncoder: any RUEntitlementRequestEncoderProtocol
    public let responseDecoder: any RUEntitlementResponseDecoderProtocol

    public init(
        requestEncoder: any RUEntitlementRequestEncoderProtocol,
        responseDecoder: any RUEntitlementResponseDecoderProtocol
    ) {
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
    }
}

public struct RUBillingWireAdapters: Sendable {
    public let catalog: RUCatalogWireAdapters
    public let checkout: RUCheckoutWireAdapters
    public let paymentStatus: RUPaymentStatusWireAdapters
    public let cancellation: RUCancellationWireAdapters
    public let entitlement: RUEntitlementWireAdapters

    public init(
        catalog: RUCatalogWireAdapters,
        checkout: RUCheckoutWireAdapters,
        paymentStatus: RUPaymentStatusWireAdapters,
        cancellation: RUCancellationWireAdapters,
        entitlement: RUEntitlementWireAdapters
    ) {
        self.catalog = catalog
        self.checkout = checkout
        self.paymentStatus = paymentStatus
        self.cancellation = cancellation
        self.entitlement = entitlement
    }

    public static let broadApps = RUBillingWireAdapters(
        catalog: RUCatalogWireAdapters(
            requestEncoder: BroadAppsRUBillingWireContract(),
            responseDecoder: BroadAppsRUCatalogResponseDecoder()
        ),
        checkout: RUCheckoutWireAdapters(
            requestEncoder: BroadAppsRUBillingWireContract(),
            responseDecoder: BroadAppsRUBillingWireContract()
        ),
        paymentStatus: RUPaymentStatusWireAdapters(
            requestEncoder: BroadAppsRUBillingWireContract(),
            responseDecoder: BroadAppsRUBillingWireContract()
        ),
        cancellation: RUCancellationWireAdapters(
            requestEncoder: BroadAppsRUBillingWireContract(),
            responseDecoder: BroadAppsRUBillingWireContract()
        ),
        entitlement: RUEntitlementWireAdapters(
            requestEncoder: BroadAppsRUBillingWireContract(),
            responseDecoder: BroadAppsRUBillingWireContract()
        )
    )

    /// Uses the standard checkout/status contracts together with the flat
    /// `{ products: [...] }` catalog used by current BroadApps backends.
    public static func broadAppsFlatCatalog(
        supportedMethods: [CheckoutMethod]
    ) -> RUBillingWireAdapters {
        RUBillingWireAdapters(
            catalog: RUCatalogWireAdapters(
                requestEncoder: BroadAppsRUBillingWireContract(),
                responseDecoder: FlatRUCatalogResponseDecoder(
                    supportedMethods: supportedMethods
                )
            ),
            checkout: broadApps.checkout,
            paymentStatus: broadApps.paymentStatus,
            cancellation: broadApps.cancellation,
            entitlement: broadApps.entitlement
        )
    }
}
