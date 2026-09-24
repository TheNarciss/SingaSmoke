import Foundation

/// French display strings for distances and durations.
public enum Format {
    /// "8 m", "350 m", "1,2 km", "12 km".
    public static func distance(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "—" }
        if meters < 10 { return "\(max(1, Int(meters.rounded()))) m" }
        if meters < 100 { return "\(Int((meters / 5).rounded()) * 5) m" }
        if meters < 950 { return "\(Int((meters / 10).rounded()) * 10) m" }
        let km = meters / 1000
        if km < 9.95 {
            let tenths = Int((km * 10).rounded())
            return "\(tenths / 10),\(tenths % 10) km"
        }
        return "\(Int(km.rounded())) km"
    }

    /// "< 1 min", "5 min", "1 h 05".
    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest < 10 ? "\(minutes / 60) h 0\(rest)" : "\(minutes / 60) h \(rest)"
    }

    /// "350 m · 5 min à pied", or "≈ 450 m · 6 min à pied" for an estimate.
    public static func walking(_ w: WalkingDistance) -> String {
        "\(w.isEstimate ? "≈ " : "")\(distance(w.meters)) · \(duration(w.seconds)) à pied"
    }

    /// Spoken version for VoiceOver: "350 mètres, 5 minutes à pied, estimation".
    public static func spokenWalking(_ w: WalkingDistance) -> String {
        let meters = w.meters
        let distanceText: String
        if meters < 950 {
            distanceText = "\(Int((meters / 10).rounded()) * 10) mètres"
        } else {
            let tenths = Int((meters / 100).rounded())
            distanceText = "\(tenths / 10) virgule \(tenths % 10) kilomètres"
        }
        let minutes = max(1, Int((w.seconds / 60).rounded()))
        return "\(distanceText), \(minutes) minute\(minutes > 1 ? "s" : "") à pied\(w.isEstimate ? ", estimation" : "")"
    }

    /// "2026-09-19" -> "19/09/2026".
    public static func date(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return nil }
        return "\(parts[2])/\(parts[1])/\(parts[0])"
    }
}
