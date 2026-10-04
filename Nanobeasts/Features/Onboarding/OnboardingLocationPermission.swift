import CoreLocation
import Combine

/// Permission only. This manager never requests coordinates or starts a workout.
@MainActor
final class OnboardingLocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRequesting = false
    @Published private(set) var denied = false
    private let manager = CLLocationManager()
    private var authorizationReply: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        manager.delegate = self
        refreshStatus()
    }

    func request() async -> Bool {
        guard !isRequesting else { return false }
        isRequesting = true
        defer { isRequesting = false }
        refreshStatus()
        guard !denied else { return false }
        let authorized: Bool
        if manager.authorizationStatus == .notDetermined {
            authorized = await withCheckedContinuation { reply in
                authorizationReply = reply
                manager.requestWhenInUseAuthorization()
            }
        } else { authorized = hasAccess }
        guard authorized else { return false }
        if manager.accuracyAuthorization == .reducedAccuracy {
            await withCheckedContinuation { (reply: CheckedContinuation<Void, Never>) in
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WorkoutRoute") { _ in
                    reply.resume()
                }
            }
        }
        return hasAccess
    }

    var hasPreciseLocation: Bool { hasAccess && manager.accuracyAuthorization == .fullAccuracy }

    private var hasAccess: Bool {
        manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
    }

    func refreshStatus() {
        denied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshStatus()
            guard self.manager.authorizationStatus != .notDetermined, let reply = self.authorizationReply else { return }
            self.authorizationReply = nil
            reply.resume(returning: self.hasAccess)
        }
    }
}
