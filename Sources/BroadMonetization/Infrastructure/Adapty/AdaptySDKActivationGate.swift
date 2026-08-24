import Adapty
import Foundation

/// Owns the process-global Adapty SDK identity and lends generation-bound
/// operation leases to one composition at a time.
///
/// Calls belonging to the active composition may run concurrently. A subject
/// transition waits until every active SDK operation finishes, then retires the
/// previous composition before calling `identify` or `logout`. Retired
/// repositories fail closed instead of switching the SDK back to an old user.
actor AdaptySDKActivationGate {
    static let shared = AdaptySDKActivationGate()

    private var activatedSettings: ActivationSettings?
    private var currentCompositionID: AdaptySDKCompositionID?
    private var currentSubject: EntitlementSubject?
    private var latestRequestedCompositionSequence: UInt64?
    private var generation: UInt64 = 0
    private var activeLeases: [UUID: OperationLease] = [:]
    private var preparation: InFlightPreparation?
    private var stateWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Runs the complete SDK-facing portion of an operation under one lease.
    /// Returning `nil` means activation, identity binding or composition
    /// ownership could not be proven; the caller must map that to a safe result.
    func perform<Result: Sendable>(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        compositionID: AdaptySDKCompositionID,
        operation: @Sendable () async -> Result
    ) async -> Result? {
        guard let lease = await acquire(
            configuration: configuration,
            identityProvider: identityProvider,
            compositionID: compositionID
        ) else {
            return nil
        }

        let result = await operation()
        release(lease)
        return result
    }
}

private extension AdaptySDKActivationGate {
    struct ActivationSettings: Equatable, Sendable {
        let apiKey: String
        let observerMode: Bool
        let idfaCollectionDisabled: Bool
        let ipAddressCollectionDisabled: Bool
        let fallbackFileURL: URL?

        init(configuration: AdaptyPlatformConfiguration) {
            apiKey = configuration.apiKey
            observerMode = configuration.observerMode
            idfaCollectionDisabled = configuration.idfaCollectionDisabled
            ipAddressCollectionDisabled = configuration.ipAddressCollectionDisabled
            fallbackFileURL = configuration.fallbackFileURL
        }
    }

    struct OperationLease: Equatable, Sendable {
        let id: UUID
        let compositionID: AdaptySDKCompositionID
        let generation: UInt64
    }

    struct InFlightPreparation {
        let id: UUID
        let compositionID: AdaptySDKCompositionID
        let subject: EntitlementSubject
        let settings: ActivationSettings
        let task: Task<Bool, Never>
    }

    struct AcquisitionRequest {
        let configuration: AdaptyPlatformConfiguration
        let identityProvider: any AdaptyIdentityProviderProtocol
        let compositionID: AdaptySDKCompositionID
        let settings: ActivationSettings
    }

    enum AcquisitionStep {
        case acquired(OperationLease)
        case retry
        case failed
    }

    func acquire(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        compositionID: AdaptySDKCompositionID
    ) async -> OperationLease? {
        let request = AcquisitionRequest(
            configuration: configuration,
            identityProvider: identityProvider,
            compositionID: compositionID,
            settings: ActivationSettings(configuration: configuration)
        )

        while !Task.isCancelled {
            switch await nextAcquisitionStep(for: request) {
            case let .acquired(lease):
                return lease
            case .retry:
                continue
            case .failed:
                return nil
            }
        }

        return nil
    }

    func nextAcquisitionStep(
        for request: AcquisitionRequest
    ) async -> AcquisitionStep {
        guard !request.compositionID.isRetired else {
            return .failed
        }
        // An in-flight first activation already establishes the only immutable
        // settings that may commit to the process-global SDK. A contender with
        // different settings must not raise the composition high-water mark and
        // poison the coherent activation that is already running.
        let establishedSettings = activatedSettings ?? preparation?.settings
        guard establishedSettings == nil || establishedSettings == request.settings else {
            // Adapty is process-global and cannot be safely reactivated with
            // another key or immutable activation options.
            request.compositionID.retire()
            return .failed
        }
        guard acceptLatestComposition(request.compositionID) else {
            return .failed
        }
        if let preparation {
            return await awaitPreparation(preparation, for: request)
        }
        if let currentCompositionID {
            return await acquireFromCurrentComposition(currentCompositionID, for: request)
        }
        return await beginPreparation(for: request)
    }

    func awaitPreparation(
        _ preparation: InFlightPreparation,
        for request: AcquisitionRequest
    ) async -> AcquisitionStep {
        guard preparation.compositionID == request.compositionID,
              preparation.subject == request.configuration.subject,
              preparation.settings == request.settings
        else {
            await waitForStateChange()
            return .retry
        }

        let succeeded = await preparation.task.value
        finishPreparation(preparation, succeeded: succeeded)
        return succeeded ? .retry : .failed
    }

    func acquireFromCurrentComposition(
        _ currentCompositionID: AdaptySDKCompositionID,
        for request: AcquisitionRequest
    ) async -> AcquisitionStep {
        if currentCompositionID == request.compositionID {
            guard currentSubject == request.configuration.subject else {
                return .failed
            }
            return .acquired(makeLease(compositionID: request.compositionID))
        }

        guard activeLeases.isEmpty else {
            await waitForStateChange()
            return .retry
        }

        // Once a new composition requests ownership, the previous one must
        // never be able to revive an obsolete subject later.
        currentCompositionID.retire()
        self.currentCompositionID = nil
        currentSubject = nil
        return await beginPreparation(for: request)
    }

    func beginPreparation(
        for request: AcquisitionRequest
    ) async -> AcquisitionStep {
        let preparation = startPreparation(
            configuration: request.configuration,
            identityProvider: request.identityProvider,
            compositionID: request.compositionID,
            settings: request.settings
        )
        let succeeded = await preparation.task.value
        finishPreparation(preparation, succeeded: succeeded)
        return succeeded ? .retry : .failed
    }

    func makeLease(
        compositionID: AdaptySDKCompositionID
    ) -> OperationLease {
        let lease = OperationLease(
            id: UUID(),
            compositionID: compositionID,
            generation: generation
        )
        activeLeases[lease.id] = lease
        return lease
    }

    func startPreparation(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        compositionID: AdaptySDKCompositionID,
        settings: ActivationSettings
    ) -> InFlightPreparation {
        let wasActivated = activatedSettings != nil
        let task = Task {
            await Self.performPreparation(
                configuration: configuration,
                identityProvider: identityProvider,
                wasActivated: wasActivated
            )
        }
        let preparation = InFlightPreparation(
            id: UUID(),
            compositionID: compositionID,
            subject: configuration.subject,
            settings: settings,
            task: task
        )
        self.preparation = preparation
        return preparation
    }

    func finishPreparation(
        _ candidate: InFlightPreparation,
        succeeded: Bool
    ) {
        guard preparation?.id == candidate.id else {
            return
        }

        preparation = nil
        if succeeded {
            // The SDK mutation is already committed even if a newer
            // composition arrived while it was in flight. Preserve activation
            // settings, but only the newest token may become an operation
            // owner. The newer request will immediately rebind the identity.
            activatedSettings = candidate.settings
            generation &+= 1

            if latestRequestedCompositionSequence == candidate.compositionID.sequence,
               !candidate.compositionID.isRetired {
                currentCompositionID = candidate.compositionID
                currentSubject = candidate.subject
            } else {
                candidate.compositionID.retire()
                currentCompositionID = nil
                currentSubject = nil
            }
        } else if latestRequestedCompositionSequence != candidate.compositionID.sequence {
            candidate.compositionID.retire()
        }
        resumeStateWaiters()
    }

    func acceptLatestComposition(
        _ compositionID: AdaptySDKCompositionID
    ) -> Bool {
        if let latestRequestedCompositionSequence {
            guard compositionID.sequence >= latestRequestedCompositionSequence else {
                compositionID.retire()
                return false
            }
            if compositionID.sequence > latestRequestedCompositionSequence {
                self.latestRequestedCompositionSequence = compositionID.sequence
            }
        } else {
            latestRequestedCompositionSequence = compositionID.sequence
        }
        return true
    }

    func release(_ lease: OperationLease) {
        guard activeLeases[lease.id] == lease else {
            return
        }

        activeLeases.removeValue(forKey: lease.id)
        if activeLeases.isEmpty {
            resumeStateWaiters()
        }
    }

    func waitForStateChange() async {
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                stateWaiters[waiterID] = continuation
            }
        } onCancel: {
            Task {
                await self.resumeStateWaiter(waiterID)
            }
        }
    }

    func resumeStateWaiter(_ waiterID: UUID) {
        stateWaiters.removeValue(forKey: waiterID)?.resume()
    }

    func resumeStateWaiters() {
        let waiters = Array(stateWaiters.values)
        stateWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    static func performPreparation(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        wasActivated: Bool
    ) async -> Bool {
        guard !Task.isCancelled else {
            return false
        }

        let identity = await identityProvider.identity(for: configuration.subject)
        if let identity {
            guard identity.subject == configuration.subject else {
                return false
            }
        } else {
            guard configuration.subject == .anonymous else {
                return false
            }
        }
        guard !Task.isCancelled else {
            return false
        }

        do {
            if wasActivated {
                if let identity {
                    try await Adapty.identify(
                        identity.customerUserID,
                        withAppAccountToken: identity.appAccountToken
                    )
                } else {
                    try await Adapty.logout()
                }
            } else {
                if let fallbackFileURL = configuration.fallbackFileURL {
                    // Adapty owns and validates this Dashboard-generated file.
                    // Register it before activation so the first paywall load
                    // can use the same provider payload without a second gate.
                    try await Adapty.setFallback(fileURL: fallbackFileURL)
                }
                let builder = AdaptyConfiguration
                    .builder(withAPIKey: configuration.apiKey)
                    .with(
                        customerUserId: identity?.customerUserID,
                        withAppAccountToken: identity?.appAccountToken
                    )
                    .with(observerMode: configuration.observerMode)
                    .with(idfaCollectionDisabled: configuration.idfaCollectionDisabled)
                    .with(ipAddressCollectionDisabled: configuration.ipAddressCollectionDisabled)
                try await Adapty.activate(with: builder.build())
            }
            // The SDK mutation is process-global and already committed. Record
            // it even when the requesting task was cancelled while awaiting the
            // SDK; acquire() will observe cancellation and withhold a lease.
            return true
        } catch {
            return false
        }
    }
}
