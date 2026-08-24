import Foundation

/// Typed values shared with host Debug configurations. A store rejects force
/// modes unless the host explicitly unlocks manual overrides.
public enum RUBillingDebugOverrideMode: String, CaseIterable, Equatable, Sendable {
    case followAdapty = "follow-adapty"
    case forceEnabled = "force-enabled"
    case forceDisabled = "force-disabled"
}

/// A process-local Debug control shared by method resolution and the final
/// checkout recheck. It never persists or mutates Adapty Remote Config.
public final class RUBillingDebugOverrideStore: @unchecked Sendable {
    private let lock = NSLock()
    private let allowsManualOverrides: Bool
    private var mode: RUBillingDebugOverrideMode

    public init(
        initialMode: RUBillingDebugOverrideMode = .followAdapty,
        allowsManualOverrides: Bool = false
    ) {
        self.allowsManualOverrides = allowsManualOverrides
        mode = allowsManualOverrides ? initialMode : .followAdapty
    }

    public var currentMode: RUBillingDebugOverrideMode {
        lock.lock()
        defer { lock.unlock() }
        return mode
    }

    public func update(_ mode: RUBillingDebugOverrideMode) {
        lock.lock()
        self.mode = allowsManualOverrides ? mode : .followAdapty
        lock.unlock()
    }
}
