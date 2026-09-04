import Foundation

/// Feeds monetization events to a ``SpecialOfferCampaignCoordinator`` on their way
/// to the project's own analytics destination.
///
/// This is the whole wiring for "the offer follows the paywall": a composition
/// passes the relay where it used to pass its analytics, and connects the
/// coordinator once it exists. The coordinator needs the paywall use case, which
/// needs the composed services, which need the analytics — so the connection is a
/// second step rather than a constructor argument.
///
/// ```swift
/// let relay = SpecialOfferCampaignAnalyticsRelay(wrapping: appAnalytics)
/// let services = BroadMonetizationServices(analytics: relay, ...)
/// let coordinator = SpecialOfferCampaignCoordinator(resolve: resolver, configuration: configuration)
/// await relay.connect(coordinator)
/// ```
///
/// Events reach the coordinator on a task of their own, so resolving a campaign
/// never delays analytics delivery or the paywall that emitted the event.
public actor SpecialOfferCampaignAnalyticsRelay: MonetizationAnalyticsProtocol {
    private let destination: any MonetizationAnalyticsProtocol
    private var coordinator: SpecialOfferCampaignCoordinator?

    /// Deliveries are chained rather than spawned independently: a purchase that
    /// ends the campaign and a close that would start one must reach the
    /// coordinator in the order they happened, or a cleared window is reopened.
    private var pendingDelivery: Task<Void, Never>?

    public init(wrapping destination: any MonetizationAnalyticsProtocol) {
        self.destination = destination
    }

    public func connect(_ coordinator: SpecialOfferCampaignCoordinator) {
        self.coordinator = coordinator
    }

    public func track(_ event: MonetizationAnalyticsEvent) async {
        if let coordinator {
            let previous = pendingDelivery
            pendingDelivery = Task {
                await previous?.value
                await coordinator.handle(event)
            }
        }
        await destination.track(event)
    }
}
