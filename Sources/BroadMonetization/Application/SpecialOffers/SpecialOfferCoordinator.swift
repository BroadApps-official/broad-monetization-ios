import Foundation

/// Owns the standard "ordinary paywall close -> Special Offer" transition and
/// resets the cadence after confirmed purchase or restore events.
public actor SpecialOfferCoordinator {
    private let resolve: any ResolveSpecialOfferUseCaseProtocol
    private let configuration: SpecialOfferConfiguration
    private let followedPlacementIDs: Set<PlacementID>
    private let continuation: AsyncStream<SpecialOfferResolution>.Continuation

    public nonisolated let decisions: AsyncStream<SpecialOfferResolution>

    private var isResolving = false

    public init(
        resolve: any ResolveSpecialOfferUseCaseProtocol,
        configuration: SpecialOfferConfiguration,
        followedPlacementIDs: Set<PlacementID>? = nil
    ) {
        self.resolve = resolve
        self.configuration = configuration
        self.followedPlacementIDs = followedPlacementIDs ?? [configuration.gatePlacementID]
        let (stream, continuation) = AsyncStream<SpecialOfferResolution>.makeStream(
            bufferingPolicy: .bufferingNewest(4)
        )
        decisions = stream
        self.continuation = continuation
    }

    public func handle(_ event: MonetizationAnalyticsEvent) async {
        switch event {
        case let .paywallClosed(context, reason):
            await handlePaywallClose(context, reason: reason)
        case .purchaseSuccess, .restoreSuccess:
            _ = await resolve.resetCycle(configuration: configuration)
        default:
            break
        }
    }

    @discardableResult
    public func resolveNow() async -> SpecialOfferResolution? {
        guard !isResolving else {
            return nil
        }
        isResolving = true
        let resolution = await resolve(configuration: configuration)
        isResolving = false
        continuation.yield(resolution)
        return resolution
    }

    public func finish() {
        continuation.finish()
    }

    private func handlePaywallClose(
        _ context: PaywallAnalyticsContext,
        reason: PaywallCloseReason
    ) async {
        switch reason {
        case .purchased:
            _ = await resolve.resetCycle(configuration: configuration)
        case .dismissed:
            guard shouldFollow(context) else {
                return
            }
            await resolveNow()
        case .unavailable, .navigation:
            break
        }
    }

    private func shouldFollow(_ context: PaywallAnalyticsContext) -> Bool {
        guard context.requestedPlacementID != configuration.placementID,
              context.resolvedPlacementID != configuration.placementID
        else {
            return false
        }
        return followedPlacementIDs.contains(context.requestedPlacementID)
    }
}
