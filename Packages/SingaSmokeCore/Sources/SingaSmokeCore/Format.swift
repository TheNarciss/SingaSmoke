import Foundation

/// Display strings for distances, durations and dates (British English, as in Singapore).
public enum Format {
    /// "8 m", "350 m", "1.2 km", "12 km".
    public static func distance(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "—" }
        if meters < 10 { return "\(max(1, Int(meters.rounded()))) m" }
        if meters < 100 { return "\(Int((meters / 5).rounded()) * 5) m" }
        if meters < 950 { return "\(Int((meters / 10).rounded()) * 10) m" }
        let km = meters / 1000
        if km < 9.95 {
            let tenths = Int((km * 10).rounded())
            return "\(tenths / 10).\(tenths % 10) km"
        }
        return "\(Int(km.rounded())) km"
    }

    /// "< 1 min", "5 min", "1 h 5 min".
    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest) min"
    }

    /// "350 m · 5 min walk", or "≈ 450 m · 6 min walk" for an estimate.
    public static func walking(_ w: WalkingDistance) -> String {
        "\(w.isEstimate ? "≈ " : "")\(distance(w.meters)) · \(duration(w.seconds)) walk"
    }

    /// Spoken version for VoiceOver: "350 metres, 5 minutes on foot, estimated".
    public static func spokenWalking(_ w: WalkingDistance) -> String {
        let meters = w.meters
        let distanceText: String
        if meters < 950 {
            distanceText = "\(Int((meters / 10).rounded()) * 10) metres"
        } else {
            let tenths = Int((meters / 100).rounded())
            distanceText = "\(tenths / 10).\(tenths % 10) kilometres"
        }
        let minutes = max(1, Int((w.seconds / 60).rounded()))
        return "\(distanceText), \(minutes) minute\(minutes > 1 ? "s" : "") on foot\(w.isEstimate ? ", estimated" : "")"
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "2026-09-19" -> "19 Sep 2026".
    public static func date(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), (1...12).contains(month), let day = Int(parts[2]) else { return nil }
        return "\(day) \(months[month - 1]) \(parts[0])"
    }
}
