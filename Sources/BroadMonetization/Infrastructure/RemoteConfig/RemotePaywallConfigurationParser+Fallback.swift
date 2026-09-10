extension RemotePaywallConfigurationParser {
    /// Resolve whole alias groups before parsing, so false, null and malformed
    /// placement values cannot be replaced by a valid main alias.
    func parse(
        _ dictionary: [String: Any],
        fallback: [String: Any]
    ) -> RemotePaywallConfiguration {
        var merged = dictionary
        for aliases in fallbackKeyGroups where !aliases.contains(where: dictionary.keys.contains) {
            for alias in aliases {
                if let value = fallback[alias] {
                    merged[alias] = value
                }
            }
        }
        return parse(merged)
    }
}
