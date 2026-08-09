import Adapty

actor AdaptyProductRegistry {
    private let retainedReleasedPresentationLimit: Int
    private var entries: [PaywallPresentationID: Entry] = [:]
    private var releasedPresentationOrder: [PaywallPresentationID] = []

    init(retainedPresentationLimit: Int = 8) {
        precondition(retainedPresentationLimit > 0, "Retained presentation limit must be positive")
        retainedReleasedPresentationLimit = retainedPresentationLimit
    }

    func store(
        paywall: AdaptyPaywall,
        paywallReference: PaywallReference,
        presentationID: PaywallPresentationID,
        products: [(reference: ProductReference, product: any AdaptyPaywallProduct)],
        retainedForCohort: Bool
    ) {
        removeReleasedOrderEntry(for: presentationID)
        entries[presentationID] = Entry(
            paywall: paywall,
            paywallReference: paywallReference,
            products: products,
            isReleased: false,
            isRetainedForCohort: retainedForCohort,
            hasReservedShow: false
        )
    }

    func product(
        for selection: ProductSelection
    ) -> (any AdaptyPaywallProduct)? {
        guard let entry = entries[selection.paywallPresentationID],
              !entry.isReleased,
              selection.paywallReference == entry.paywallReference
        else {
            return nil
        }
        return entry.products.first { item in
            item.reference == selection.product.reference
        }?.product
    }

    /// Atomically verifies that a real SDK paywall exists and then reserves its
    /// one allowed `logShowPaywall` call. A missing/released presentation never
    /// consumes the reservation, so a valid later lookup is not poisoned.
    func reservePaywallForShow(
        presentationID: PaywallPresentationID,
        reference: PaywallReference
    ) -> AdaptyPaywall? {
        guard var entry = entries[presentationID],
              !entry.isReleased,
              entry.paywallReference == reference,
              !entry.hasReservedShow
        else {
            return nil
        }

        entry.hasReservedShow = true
        entries[presentationID] = entry
        return entry.paywall
    }

    func clonePresentation(
        from sourcePresentationID: PaywallPresentationID,
        reference: PaywallReference,
        to presentationID: PaywallPresentationID
    ) -> Bool {
        guard let entry = entries[sourcePresentationID],
              entry.paywallReference == reference
        else {
            return false
        }

        removeReleasedOrderEntry(for: presentationID)
        entries[presentationID] = Entry(
            paywall: entry.paywall,
            paywallReference: entry.paywallReference,
            products: entry.products,
            isReleased: false,
            isRetainedForCohort: false,
            hasReservedShow: false
        )
        return true
    }

    /// Ends the temporary pin owned by one coalesced repository load. The source
    /// stays cloneable until every caller that joined that load has received its
    /// own presentation, even when the source caller was cancelled or closed.
    func endCohortRetention(
        presentationID: PaywallPresentationID,
        reference: PaywallReference
    ) {
        guard var entry = entries[presentationID],
              entry.paywallReference == reference
        else {
            return
        }

        entry.isRetainedForCohort = false
        entries[presentationID] = entry
        trimReleasedIfNeeded()
    }

    /// Marks a presentation terminal. Live entries are never trimmed; only
    /// released entries participate in the bounded retention policy.
    func release(
        presentationID: PaywallPresentationID,
        reference: PaywallReference
    ) {
        guard var entry = entries[presentationID],
              entry.paywallReference == reference,
              !entry.isReleased
        else {
            return
        }

        entry.isReleased = true
        entries[presentationID] = entry
        releasedPresentationOrder.append(presentationID)
        trimReleasedIfNeeded()
    }

    func removeAll() {
        entries.removeAll()
        releasedPresentationOrder.removeAll()
    }
}

private extension AdaptyProductRegistry {
    struct Entry {
        let paywall: AdaptyPaywall
        let paywallReference: PaywallReference
        let products: [(reference: ProductReference, product: any AdaptyPaywallProduct)]
        var isReleased: Bool
        var isRetainedForCohort: Bool
        var hasReservedShow: Bool
    }

    func removeReleasedOrderEntry(
        for presentationID: PaywallPresentationID
    ) {
        releasedPresentationOrder.removeAll { storedID in
            storedID == presentationID
        }
    }

    func trimReleasedIfNeeded() {
        while releasedPresentationOrder.count > retainedReleasedPresentationLimit {
            guard let removalIndex = releasedPresentationOrder.firstIndex(where: { presentationID in
                guard let entry = entries[presentationID] else {
                    return true
                }
                return entry.isReleased && !entry.isRetainedForCohort
            }) else {
                return
            }

            let removedID = releasedPresentationOrder.remove(at: removalIndex)
            guard entries[removedID]?.isReleased == true else {
                continue
            }
            entries.removeValue(forKey: removedID)
        }
    }
}
