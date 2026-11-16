import ActivityKit
import Foundation

// Shared Live Activity attributes (build 65). This file is compiled
// into BOTH the main app (so it can start/update the activity) and the
// widget extension (so it can render it). Keep it dependency-free apart
// from ActivityKit/Foundation so it builds in both targets.
// The app localizes all display labels and passes them in, so the
// widget never needs its own localization or App Groups.
struct TripAttributes: ActivityAttributes {
    // Fixed for the trip (set at start).
    var fromName: String
    var toName: String
    var lineName: String
    var themeHex: String   // 6-digit hex, city theme colour
    var totalStops: Int
    // Localized labels (the app fills these from its LANG table).
    var nextLabel: String      // e.g. "下一站" / "Next stop"
    var stopsFormat: String    // e.g. "还剩 {n} 站" / "{n} stops left"
    var tripLabel: String      // e.g. "行程" / "Trip"
    var arrivedLabel: String   // e.g. "已到达" / "Arrived"

    struct ContentState: Codable, Hashable {
        var nextStation: String
        var remainingStops: Int
        var arrivalDate: Date
        var status: String   // "active" or "arrived"
    }
}
