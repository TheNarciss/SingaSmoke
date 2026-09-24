import Foundation

/// A position from the phone, with its error radius (CLLocation.horizontalAccuracy).
public struct GPSFix: Sendable, Equatable {
    public let coordinate: Coordinate
    /// Metres; negative means unknown.
    public let horizontalAccuracy: Double

    public init(coordinate: Coordinate, horizontalAccuracy: Double) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
    }

    /// The error radius the verdict reasons with: at least 5 m, at most 100 m, 50 m if unknown.
    public var effectiveAccuracy: Double {
        guard horizontalAccuracy > 0, horizontalAccuracy.isFinite else { return 50 }
        return min(max(horizontalAccuracy, 5), 100)
    }
}

/// A zone near or around the user, and the way out of it.
public struct ZoneHit: Sendable, Identifiable {
    public let zone: NoSmokingZone
    /// Negative inside, positive outside, metres.
    public let signedDistance: Double
    /// Inside by more than the GPS error: no doubt about it.
    public let isCertain: Bool
    /// Nearest point just outside the zone.
    public let exit: Coordinate
    public let exitDistance: Double
    public let exitDirection: CompassDirection

    public var id: String { zone.id }

    init(zone: NoSmokingZone, signedDistance: Double, from p: Coordinate, accuracy: Double) {
        self.zone = zone
        self.signedDistance = signedDistance
        isCertain = signedDistance <= -accuracy
        exit = zone.exitPoint(from: p)
        exitDistance = Geo.distance(p, exit)
        exitDirection = CompassDirection(bearing: Geo.bearing(from: p, to: exit))
    }
}

/// What the banner says. The order of the checks is the order of the cases.
public enum Verdict: Sendable {
    /// Location refused or not yet known.
    case noLocation
    /// The fix is not in Singapore: nothing to judge.
    case outsideSingapore
    /// Within a few metres of a smoking spot. For an NEA yellow box this wins over the
    /// Orchard zone around it: that is the exception the box exists for.
    case atSpot(SmokingSpot, distance: Double, caution: ZoneHit?)
    /// Inside at least one no-smoking zone. `spotHere` is an OpenStreetMap spot that claims
    /// otherwise; the regulation wins, the UI mentions it.
    case prohibited(ZoneHit, alsoIn: [ZoneHit], spotHere: SmokingSpot?)
    /// Outside, but the edge of a zone is within the GPS error.
    case nearZone(ZoneHit)
    /// No known restriction here. Not a green light: indoor places, covered walkways,
    /// void decks and building entrances are not on any map. `nearby` is the closest zone within 50 m.
    case clear(nearby: ZoneHit?)
}

public enum VerdictEngine {
    /// Distance under which the user is considered to be at a spot, before GPS error.
    public static let atSpotRadius: Double = 20

    public static func evaluate(fix: GPSFix?, spots: [SmokingSpot], index: ZoneIndex) -> Verdict {
        guard let fix else { return .noLocation }
        let p = fix.coordinate
        guard Geo.singapore.contains(p) else { return .outsideSingapore }
        let accuracy = fix.effectiveAccuracy

        // 1. At an NEA yellow box: allowed, whatever zone surrounds it.
        if let nea = nearestSpot(to: p, in: spots, where: { $0.source == .nea }, within: max(atSpotRadius, accuracy)) {
            return .atSpot(nea.spot, distance: nea.distance, caution: nil)
        }

        let around = index.zones(near: p, radius: max(accuracy, 50))
        func hit(_ entry: (zone: NoSmokingZone, signedDistance: Double)) -> ZoneHit {
            ZoneHit(zone: entry.zone, signedDistance: entry.signedDistance, from: p, accuracy: accuracy)
        }

        // 2. Inside a zone. Official zones first, then the deepest.
        let inside = around.filter { $0.signedDistance <= 0 }
            .sorted { lhs, rhs in
                let l = lhs.zone.reliability == .official, r = rhs.zone.reliability == .official
                return l != r ? l : lhs.signedDistance < rhs.signedDistance
            }
        let communitySpot = nearestSpot(to: p, in: spots, where: { $0.source == .osmArea || $0.source == .osmVenue },
                                        within: atSpotRadius)
        if let primary = inside.first {
            return .prohibited(hit(primary), alsoIn: inside.dropFirst().map(hit), spotHere: communitySpot?.spot)
        }

        let nearest = around.first { $0.signedDistance > 0 }

        // 3. At a community-mapped spot, outside every zone.
        if let community = communitySpot {
            let caution = nearest.flatMap { $0.signedDistance <= accuracy ? hit($0) : nil }
            return .atSpot(community.spot, distance: community.distance, caution: caution)
        }

        // 4. Close to a zone's edge, within the GPS error.
        if let edge = nearest, edge.signedDistance <= accuracy {
            return .nearZone(hit(edge))
        }

        // 5. Nothing known here.
        return .clear(nearby: nearest.flatMap { $0.signedDistance <= 50 ? hit($0) : nil })
    }

    static func nearestSpot(to p: Coordinate, in spots: [SmokingSpot], where include: (SmokingSpot) -> Bool,
                            within radius: Double) -> (spot: SmokingSpot, distance: Double)? {
        var best: (spot: SmokingSpot, distance: Double)?
        for spot in spots where include(spot) {
            let d = Geo.distance(p, spot.coordinate)
            if d <= radius, d < (best?.distance ?? .infinity) { best = (spot, d) }
        }
        return best
    }
}
