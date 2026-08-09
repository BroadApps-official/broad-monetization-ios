public enum EntitlementSource: String, CaseIterable, Codable, Sendable {
    case apple
    case primaryBackend = "primary-backend"
    case ruBilling = "ru-billing"
}
