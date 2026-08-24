import CoreFoundation
import Foundation

public struct RemotePaywallConfigurationParser: Sendable {
    private let keys: RemoteConfigKeyRegistry

    public init(keys: RemoteConfigKeyRegistry = .broadApps) {
        self.keys = keys
    }

    public func parse(
        _ dictionary: [String: Any]
    ) -> RemotePaywallConfiguration {
        let hardPaywall = value(in: dictionary, aliases: keys.hardPaywall)
            .flatMap(parseAccessPolicy)

        return RemotePaywallConfiguration(
            ruBillingGateDecision: parseRUBillingGate(in: dictionary),
            isAutomaticRevenueViewEnabled: value(
                in: dictionary,
                aliases: keys.automaticRevenueView
            ).flatMap(parseBool),
            accessPolicy: hardPaywall,
            closeDelay: value(in: dictionary, aliases: keys.closeDelay)
                .flatMap(parseNonNegativeTimeInterval),
            uiVariantID: value(in: dictionary, aliases: keys.uiVariant)
                .flatMap(parseString)
                .flatMap(validIdentifier)
                .map(PaywallUIVariantID.init(rawValue:)),
            specialOffer: parseSpecialOffer(dictionary),
            authorizesRUBillingPresentation: false
        )
    }
}

private extension RemotePaywallConfigurationParser {
    func parseRUBillingGate(
        in dictionary: [String: Any]
    ) -> RemoteRUBillingGateDecision {
        var didFindKey = false
        var didFindInvalidValue = false
        var parsedValues: [Bool] = []

        for alias in keys.ruBillingGate where dictionary.keys.contains(alias) {
            didFindKey = true
            guard let rawValue = dictionary[alias],
                  let parsed = parseBool(rawValue)
            else {
                didFindInvalidValue = true
                continue
            }
            parsedValues.append(parsed)
        }

        guard didFindKey else {
            return .absent
        }
        // An explicit kill switch always wins, including over a malformed or
        // conflicting alias with higher lookup priority.
        if parsedValues.contains(false) {
            return .disabled
        }
        guard !didFindInvalidValue,
              !parsedValues.isEmpty,
              parsedValues.allSatisfy({ $0 })
        else {
            return .invalid
        }
        return .enabled
    }

    func validIdentifier(_ value: String) -> String? {
        MonetizationIdentifierPolicy.isValid(value) ? value : nil
    }
}

private extension RemotePaywallConfigurationParser {
    func parseSpecialOffer(
        _ dictionary: [String: Any]
    ) -> SpecialOfferRemoteConfiguration? {
        let specialAliases = keys.specialOfferGate
            + keys.specialOfferDurationHours
            + keys.specialOfferCooldownHours
            + keys.crossedPrice
            + keys.crossedValue
            + keys.priceMultiplier
            + keys.specialOfferBadge
            + keys.specialOfferPeriodText
        guard specialAliases.contains(where: { dictionary.keys.contains($0) }) else {
            return nil
        }

        let windowDuration = parseOptionalSpecialOfferDuration(
            in: dictionary,
            aliases: keys.specialOfferDurationHours
        )
        let cooldownDuration = parseOptionalSpecialOfferDuration(
            in: dictionary,
            aliases: keys.specialOfferCooldownHours
        )

        return SpecialOfferRemoteConfiguration(
            // `special_offer` is the only campaign gate. Legacy duration fields
            // are retained as optional metadata for source compatibility, but
            // malformed values cannot disable the provider's explicit flag.
            isEnabled: parseSpecialOfferGate(in: dictionary),
            windowDuration: windowDuration.value,
            cooldownDuration: cooldownDuration.value,
            crossedPrice: value(in: dictionary, aliases: keys.crossedPrice)
                .flatMap(parseString),
            crossedValue: value(in: dictionary, aliases: keys.crossedValue)
                .flatMap(parsePositiveDecimal),
            priceMultiplier: value(in: dictionary, aliases: keys.priceMultiplier)
                .flatMap(parsePositiveDecimal),
            periodText: value(in: dictionary, aliases: keys.specialOfferPeriodText)
                .flatMap(parseString),
            badge: value(in: dictionary, aliases: keys.specialOfferBadge)
                .flatMap(parseString)
        )
    }

    func parseSpecialOfferGate(
        in dictionary: [String: Any]
    ) -> Bool {
        var didFindKey = false
        var didFindInvalidValue = false
        var parsedValues: [Bool] = []

        for alias in keys.specialOfferGate where dictionary.keys.contains(alias) {
            didFindKey = true
            guard let rawValue = dictionary[alias],
                  let parsed = parseBool(rawValue)
            else {
                didFindInvalidValue = true
                continue
            }
            parsedValues.append(parsed)
        }

        // The kill switch always wins. Conflicting or malformed aliases are
        // otherwise fail-closed because this flag authorizes a presentation.
        if parsedValues.contains(false) {
            return false
        }
        return didFindKey
            && !didFindInvalidValue
            && !parsedValues.isEmpty
            && parsedValues.allSatisfy { $0 }
    }

    func parseOptionalSpecialOfferDuration(
        in dictionary: [String: Any],
        aliases: [String]
    ) -> (value: TimeInterval?, isValid: Bool) {
        let presentAliases = aliases.filter(dictionary.keys.contains)
        guard !presentAliases.isEmpty else {
            return (nil, true)
        }

        var durations: [TimeInterval] = []
        for alias in presentAliases {
            guard let rawValue = dictionary[alias],
                  let duration = parsePositiveHours(rawValue)
            else {
                return (nil, false)
            }
            durations.append(duration)
        }

        guard let duration = durations.first,
              durations.allSatisfy({ $0 == duration })
        else {
            return (nil, false)
        }
        return (duration, true)
    }

    func value(
        in dictionary: [String: Any],
        aliases: [String]
    ) -> Any? {
        for alias in aliases where dictionary.keys.contains(alias) {
            return dictionary[alias]
        }
        return nil
    }

    func parseAccessPolicy(_ value: Any) -> PaywallAccessPolicy? {
        if let boolean = parseBool(value) {
            return boolean ? .hard : .soft
        }
        guard let string = parseString(value)?.lowercased() else {
            return nil
        }
        switch string {
        case "hard": return .hard
        case "soft": return .soft
        default: return nil
        }
    }

    func parseBool(_ value: Any) -> Bool? {
        if let boolean = value as? Bool {
            return boolean
        }
        if let number = value as? NSNumber {
            switch number.doubleValue {
            case 0: return false
            case 1: return true
            default: return nil
            }
        }
        guard let string = value as? String else {
            return nil
        }
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on": return true
        case "0", "false", "no", "n", "off", "": return false
        default: return nil
        }
    }

    func parseString(_ value: Any) -> String? {
        // Swift Bool bridges to NSNumber. It must not silently become the
        // display/identifier string "1" or "0" outside explicit bool fields.
        guard !isFoundationBoolean(value) else {
            return nil
        }
        let rawValue: String
        if let string = value as? String {
            rawValue = string
        } else if let number = value as? NSNumber {
            rawValue = number.stringValue
        } else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    func parseNonNegativeTimeInterval(_ value: Any) -> TimeInterval? {
        guard let number = parseDouble(value), number.isFinite, number >= 0 else {
            return nil
        }
        return number
    }

    func parsePositiveHours(_ value: Any) -> TimeInterval? {
        guard let hours = parseDouble(value), hours.isFinite, hours > 0 else {
            return nil
        }
        let seconds = hours * 3600
        return SpecialOfferDurationPolicy.isValid(seconds) ? seconds : nil
    }

    func parsePositiveDecimal(_ value: Any) -> Decimal? {
        // Foundation bridges Bool to NSNumber(0/1); campaign price metadata
        // must require a real numeric value.
        guard !isFoundationBoolean(value) else {
            return nil
        }
        let decimal: Decimal? = if let value = value as? Decimal {
            value
        } else if let number = value as? NSNumber {
            number.decimalValue
        } else if let string = value as? String {
            Decimal(
                string: string.trimmingCharacters(in: .whitespacesAndNewlines),
                locale: Locale(identifier: "en_US_POSIX")
            )
        } else {
            nil
        }

        guard let decimal, !decimal.isNaN, decimal > 0 else {
            return nil
        }
        return decimal
    }

    func parseDouble(_ value: Any) -> Double? {
        // A remote boolean is not a duration. Check before NSNumber because
        // `true as Any` also casts to NSNumber(1) through Foundation bridging.
        guard !isFoundationBoolean(value) else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let number = value as? Double {
            return number
        }
        if let integer = value as? Int {
            return Double(integer)
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func isFoundationBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else {
            return false
        }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
