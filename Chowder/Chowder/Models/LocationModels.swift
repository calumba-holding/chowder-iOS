import Foundation

enum LocationEventSource: String, Codable {
    case visitArrival = "visit_arrival"
    case visitDeparture = "visit_departure"
    case significantChange = "significant_change"
    case foregroundRefresh = "foreground_refresh"
}

struct LocationPreferences: Codable {
    var sharingEnabled: Bool = false
    var freshnessWindowMinutes: Int = 45
}

struct LocationSnapshot: Codable, Identifiable {
    var id: String = UUID().uuidString
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var timestamp: Date
    var source: LocationEventSource
    var placeName: String?
    var street: String?
    var locality: String?
    var administrativeArea: String?
    var postalCode: String?
    var country: String?
}

struct LocationSyncState: Codable {
    var lastSnapshot: LocationSnapshot?
    var pendingSnapshots: [LocationSnapshot] = []
    var lastSyncedAt: Date?
    var lastHeartbeatAt: Date?
}
