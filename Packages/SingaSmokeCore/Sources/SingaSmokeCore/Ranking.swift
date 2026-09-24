import Foundation

/// A walking distance, either from Apple's router or estimated from the straight line.
public struct WalkingDistance: Hashable, Sendable {
    public let meters: Double
    public let seconds: Double
    /// True when no route was available (offline, throttled): straight line × detour factor.
    public let isEstimate: Bool

    public init(meters: Double, seconds: Double, isEstimate: Bool) {
        self.meters = meters
        self.seconds = seconds
        self.isEstimate = isEstimate
    }

    /// Streets are not straight: in Singapore a walk is typically ~1.3× the crow-flies distance.
    public static let detourFactor = 1.3
    /// 4.8 km/h.
    public static let walkingSpeed = 4.8 / 3.6

    public static func estimate(straightLine meters: Double) -> WalkingDistance {
        let walked = meters * detourFactor
        return WalkingDistance(meters: walked, seconds: walked / walkingSpeed, isEstimate: true)
    }
}

/// Something with an identity and a position the lists can sort.
public protocol Located: Identifiable where ID == String {
    var coordinate: Coordinate { get }
}

extension SmokingSpot: Located {}
extension Retailer: Located {}

public struct RankedPlace<Item: Located>: Identifiable {
    public let item: Item
    public let straightLine: Double
    public var walking: WalkingDistance

    public var id: String { item.id }

    public init(item: Item, straightLine: Double, walking: WalkingDistance? = nil) {
        self.item = item
        self.straightLine = straightLine
        self.walking = walking ?? .estimate(straightLine: straightLine)
    }
}

public enum Ranking {
    /// The `limit` closest items by straight line, closest first.
    public static func nearest<Item: Located>(_ items: [Item], to p: Coordinate, limit: Int) -> [RankedPlace<Item>] {
        guard limit > 0 else { return [] }
        return items
            .map { RankedPlace(item: $0, straightLine: Geo.distance(p, $0.coordinate)) }
            .sorted { $0.straightLine < $1.straightLine }
            .prefix(limit)
            .map { $0 }
    }

    /// Re-sorts by walking distance once routes are known; ties keep the straight-line order.
    public static func byWalking<Item>(_ places: [RankedPlace<Item>]) -> [RankedPlace<Item>] {
        places.enumerated()
            .sorted { lhs, rhs in
                lhs.element.walking.meters != rhs.element.walking.meters
                    ? lhs.element.walking.meters < rhs.element.walking.meters
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
