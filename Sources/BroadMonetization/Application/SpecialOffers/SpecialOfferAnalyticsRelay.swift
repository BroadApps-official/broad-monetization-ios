import Foundation

/// Delivers monetization events to the standard Special Offer coordinator
/// without delaying the host's own analytics destination.
public actor SpecialOfferAnalyticsRelay: MonetizationAnalyticsProtocol {
    private let destination: any MonetizationAnalyticsProtocol
    private var coordinator: SpecialOfferCoordinator?
    private var pendingDelivery: Task<Void, Never>?

    public init(wrapping destination: any MonetizationAnalyticsProtocol) {
        self.destination = destination
    }

    public func connect(_ coordinator: SpecialOfferCoordinator) {
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
