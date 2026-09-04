import BroadCore

public extension SpecialOfferClock {
    init(
        serverTime: any ServerTimeProviderProtocol
    ) {
        self.init {
            switch await serverTime.reading() {
            case let .synchronized(date):
                .trusted(date)
            case .unverified:
                .untrusted
            }
        }
    }
}
