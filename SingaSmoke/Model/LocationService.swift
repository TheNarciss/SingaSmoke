import CoreLocation
import Observation
import SingaSmokeCore

/// "When in use" location only. Started when the app comes to the foreground, stopped when it
/// leaves: no background mode, no "always" permission, nothing stored or sent.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var fix: GPSFix?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wantsUpdates = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness   // on foot
        manager.pausesLocationUpdatesAutomatically = true
        authorization = manager.authorizationStatus
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }
    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    /// Called when the app is opened: asks the first time, then follows the user while visible.
    func start() {
        wantsUpdates = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if let last = manager.location {
                accept(last.coordinate, accuracy: last.horizontalAccuracy, age: -last.timestamp.timeIntervalSinceNow)
            }
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    /// Called when the app goes to the background.
    func stop() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
    }

    private func accept(_ coordinate: CLLocationCoordinate2D, accuracy: Double, age: TimeInterval) {
        guard accuracy >= 0, CLLocationCoordinate2DIsValid(coordinate) else { return }
        // A cached fix older than two minutes says little about where the user is now.
        if fix != nil, age > 120 { return }
        fix = GPSFix(coordinate: Coordinate(coordinate), horizontalAccuracy: accuracy)
    }

    // MARK: CLLocationManagerDelegate (delivered on the main thread, where the manager was created)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            if wantsUpdates, isAuthorized { start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = last.coordinate
        let accuracy = last.horizontalAccuracy
        let age = -last.timestamp.timeIntervalSinceNow
        MainActor.assumeIsolated { accept(coordinate, accuracy: accuracy, age: age) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient; a denial arrives through the authorization callback.
    }
}
