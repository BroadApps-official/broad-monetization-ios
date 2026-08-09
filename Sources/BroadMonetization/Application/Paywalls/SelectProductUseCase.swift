public struct SelectProductUseCase: SelectProductUseCaseProtocol {
    public init() {}

    public func callAsFunction(
        productPresentationID: ProductPresentationID,
        in paywall: PaywallPayload
    ) -> ProductSelection? {
        guard let product = paywall.products.first(where: { product in
            product.presentationID == productPresentationID
        }) else {
            return nil
        }
        return ProductSelection(paywall: paywall, product: product)
    }
}
