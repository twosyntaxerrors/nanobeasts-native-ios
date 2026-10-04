import CoreLocation

/// System permission and Nano's saved route preference are deliberately independent.
struct WatchLocationAccess {
    let status: CLAuthorizationStatus
    let accuracy: CLAccuracyAuthorization

    var needsAuthorization: Bool { status == .notDetermined }
    var isAuthorized: Bool { status == .authorizedAlways || status == .authorizedWhenInUse }
    var canRecordRoute: Bool { isAuthorized && accuracy == .fullAccuracy }

    func shouldResumeRoute(running: Bool, indoor: Bool, routeEnabled: Bool, saving: Bool) -> Bool {
        running && !indoor && routeEnabled && !saving && canRecordRoute
    }

    var notice: String? {
        switch status {
        case .denied:
            return "Location access is off. Enable it for Nano in Watch Settings → Privacy & Security → Location Services. Your GPS routes choice is still saved."
        case .restricted:
            return "Location access is restricted by this device. Your GPS routes choice is still saved."
        case .notDetermined:
            return "Choose Allow While Using App when asked to keep location access for future walks."
        case .authorizedAlways, .authorizedWhenInUse:
            return accuracy == .fullAccuracy ? nil
                : "Precise Location is off. Enable it for Nano in Location Services to record an accurate route."
        @unknown default:
            return "Location status is unavailable. Your workout can continue without a route."
        }
    }

    var settingsDescription: String {
        if canRecordRoute { return "Location is enabled. Routes start automatically with outdoor workouts." }
        return notice ?? "Location is unavailable."
    }
}
