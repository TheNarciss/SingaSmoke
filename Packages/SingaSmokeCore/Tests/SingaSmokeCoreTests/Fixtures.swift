import Foundation
@testable import SingaSmokeCore

/// Small synthetic shapes around a Singapore origin, built in metres so tests read naturally.
enum Fixtures {
    static let origin = Coordinate(latitude: 1.3000, longitude: 103.8000)
    static let projection = LocalProjection(origin: origin)

    /// The coordinate `x` metres east and `y` metres north of the origin.
    static func at(_ x: Double, _ y: Double) -> Coordinate {
        projection.unproject(x: x, y: y)
    }

    /// Axis-aligned rectangle ring, in metres from the origin, closed like GeoJSON.
    static func rect(x0: Double, y0: Double, x1: Double, y1: Double) -> [Coordinate] {
        [at(x0, y0), at(x1, y0), at(x1, y1), at(x0, y1), at(x0, y0)]
    }

    static func polygonZone(id: String, kind: ZoneKind, source: ZoneSource = .osm, buffer: Double = 0,
                            rings: [[Coordinate]]) -> NoSmokingZone {
        NoSmokingZone(id: id, kind: kind, name: nil, source: source, buffer: buffer,
                      geometry: .polygons([Polygon(rings: rings)!]))
    }

    static func pointZone(id: String, kind: ZoneKind, at c: Coordinate, radius: Double) -> NoSmokingZone {
        NoSmokingZone(id: id, kind: kind, name: nil, source: .osm, buffer: radius, geometry: .point(c))
    }

    static func spot(_ id: String, _ source: SpotSource, at c: Coordinate, airside: Bool = false) -> SmokingSpot {
        SmokingSpot(id: id, name: id, details: "", coordinate: c, source: source, isAirside: airside)
    }

    static func fix(_ c: Coordinate, accuracy: Double = 5) -> GPSFix {
        GPSFix(coordinate: c, horizontalAccuracy: accuracy)
    }
}
