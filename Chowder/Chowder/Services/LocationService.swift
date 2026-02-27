import CoreLocation
import Foundation

protocol LocationServiceDelegate: AnyObject {
    func locationServiceDidUpdateAuthorization(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization)
    func locationServiceDidReceiveSnapshot(_ snapshot: LocationSnapshot)
    func locationServiceDidFail(_ error: Error)
}

final class LocationService: NSObject, CLLocationManagerDelegate {
    weak var delegate: LocationServiceDelegate?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var sharingEnabled = false
    private var pendingOneShotSource: LocationEventSource?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
    }

    func refreshAuthorizationStatus() {
        delegate?.locationServiceDidUpdateAuthorization(
            status: manager.authorizationStatus,
            accuracy: manager.accuracyAuthorization
        )
    }

    func setSharingEnabled(_ enabled: Bool) {
        sharingEnabled = enabled
        if enabled {
            requestAuthorizationIfNeeded()
            startMonitoringIfAuthorized()
        } else {
            manager.stopMonitoringVisits()
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    func requestAuthorizationIfNeeded() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
    }

    func requestForegroundRefresh() {
        pendingOneShotSource = .foregroundRefresh
        manager.requestLocation()
    }

    private func startMonitoringIfAuthorized() {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        manager.startMonitoringVisits()
        manager.startMonitoringSignificantLocationChanges()
    }

    private func snapshot(from location: CLLocation, source: LocationEventSource) -> LocationSnapshot {
        LocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            source: source
        )
    }

    private func emit(_ snapshot: LocationSnapshot) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.locationServiceDidReceiveSnapshot(snapshot)
        }
    }

    private func enrichAndEmit(_ snapshot: LocationSnapshot) {
        let location = CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            var enriched = snapshot
            if let placemark = placemarks?.first {
                enriched.placeName = placemark.name
                enriched.street = [placemark.subThoroughfare, placemark.thoroughfare]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                enriched.locality = placemark.locality
                enriched.administrativeArea = placemark.administrativeArea
                enriched.postalCode = placemark.postalCode
                enriched.country = placemark.country
            }
            self.emit(enriched)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        delegate?.locationServiceDidUpdateAuthorization(
            status: manager.authorizationStatus,
            accuracy: manager.accuracyAuthorization
        )
        if sharingEnabled {
            startMonitoringIfAuthorized()
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard sharingEnabled else { return }
        let coord = visit.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return }

        let source: LocationEventSource = visit.departureDate == .distantFuture ? .visitArrival : .visitDeparture
        let location = CLLocation(
            coordinate: coord,
            altitude: 0,
            horizontalAccuracy: max(visit.horizontalAccuracy, 0),
            verticalAccuracy: -1,
            timestamp: visit.arrivalDate
        )
        enrichAndEmit(snapshot(from: location, source: source))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let source = pendingOneShotSource ?? .significantChange
        pendingOneShotSource = nil
        enrichAndEmit(snapshot(from: location, source: source))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pendingOneShotSource = nil
        delegate?.locationServiceDidFail(error)
    }
}
