import Foundation

/// A WGS84 position. Kept independent from CoreLocation so the logic runs anywhere.
public struct Coordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// GeoJSON order: [longitude, latitude].
    init?(geoJSON pair: [Double]) {
        guard pair.count >= 2, pair[0].isFinite, pair[1].isFinite else { return nil }
        self.init(latitude: pair[1], longitude: pair[0])
    }
}

public struct BoundingBox: Hashable, Sendable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    public init?(_ points: [Coordinate]) {
        guard let first = points.first else { return nil }
        var box = BoundingBox(minLatitude: first.latitude, maxLatitude: first.latitude,
                              minLongitude: first.longitude, maxLongitude: first.longitude)
        for p in points.dropFirst() { box.include(p) }
        self = box
    }

    public mutating func include(_ p: Coordinate) {
        minLatitude = min(minLatitude, p.latitude)
        maxLatitude = max(maxLatitude, p.latitude)
        minLongitude = min(minLongitude, p.longitude)
        maxLongitude = max(maxLongitude, p.longitude)
    }

    public func contains(_ p: Coordinate) -> Bool {
        p.latitude >= minLatitude && p.latitude <= maxLatitude
            && p.longitude >= minLongitude && p.longitude <= maxLongitude
    }

    /// The box grown by `meters` on every side.
    public func expanded(byMeters meters: Double) -> BoundingBox {
        let dLat = meters / Geo.metersPerDegreeLatitude
        let dLon = meters / Geo.metersPerDegreeLongitude(at: (minLatitude + maxLatitude) / 2)
        return BoundingBox(minLatitude: minLatitude - dLat, maxLatitude: maxLatitude + dLat,
                           minLongitude: minLongitude - dLon, maxLongitude: maxLongitude + dLon)
    }

    public var center: Coordinate {
        Coordinate(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }
}

public enum Geo {
    /// Mean Earth radius (IUGG), metres.
    public static let earthRadius = 6_371_008.8
    public static let metersPerDegreeLatitude = earthRadius * .pi / 180

    public static func metersPerDegreeLongitude(at latitude: Double) -> Double {
        metersPerDegreeLatitude * cos(latitude * .pi / 180)
    }

    /// Singapore, generously. Outside this box the app says so instead of judging.
    public static let singapore = BoundingBox(minLatitude: 1.13, maxLatitude: 1.48, minLongitude: 103.55, maxLongitude: 104.1)

    /// Great-circle distance in metres (haversine).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad
        let dLon = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`, degrees clockwise from north, in [0, 360).
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let rad = Double.pi / 180
        let lat1 = a.latitude * rad, lat2 = b.latitude * rad
        let dLon = (b.longitude - a.longitude) * rad
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) / rad
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point `meters` away from `origin` along `bearing` (flat-earth, fine under a few km).
    public static func offset(_ origin: Coordinate, meters: Double, bearing: Double) -> Coordinate {
        let rad = bearing * .pi / 180
        return Coordinate(
            latitude: origin.latitude + meters * cos(rad) / metersPerDegreeLatitude,
            longitude: origin.longitude + meters * sin(rad) / metersPerDegreeLongitude(at: origin.latitude)
        )
    }
}

/// Equirectangular projection around an origin: metres east (x) and north (y).
/// Exact enough within a few kilometres, which is all a GPS check ever needs.
public struct LocalProjection: Sendable {
    public let origin: Coordinate
    private let kx: Double
    private let ky: Double

    public init(origin: Coordinate) {
        self.origin = origin
        ky = Geo.metersPerDegreeLatitude
        kx = Geo.metersPerDegreeLongitude(at: origin.latitude)
    }

    public func project(_ c: Coordinate) -> (x: Double, y: Double) {
        ((c.longitude - origin.longitude) * kx, (c.latitude - origin.latitude) * ky)
    }

    public func unproject(x: Double, y: Double) -> Coordinate {
        Coordinate(latitude: origin.latitude + y / ky, longitude: origin.longitude + x / kx)
    }
}

/// Eight-point compass.
public enum CompassDirection: String, CaseIterable, Sendable {
    case north
    case northEast = "north-east"
    case east
    case southEast = "south-east"
    case south
    case southWest = "south-west"
    case west
    case northWest = "north-west"

    public init(bearing: Double) {
        let normalized = (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45) % 8
        self = CompassDirection.allCases[index]
    }

    /// "to the north", "to the south-west".
    public var towards: String { "to the \(rawValue)" }
}
