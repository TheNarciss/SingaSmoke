import MapKit
import SingaSmokeCore

final class SpotAnnotation: NSObject, MKAnnotation {
    let spot: SmokingSpot
    let coordinate: CLLocationCoordinate2D

    init(_ spot: SmokingSpot) {
        self.spot = spot
        coordinate = spot.coordinate.cl
    }

    var title: String? { spot.name }
    var subtitle: String? { spot.details.isEmpty ? nil : spot.details }
}

final class RetailerAnnotation: NSObject, MKAnnotation {
    let retailer: Retailer
    let coordinate: CLLocationCoordinate2D

    init(_ retailer: Retailer) {
        self.retailer = retailer
        coordinate = retailer.coordinate.cl
    }

    var title: String? { retailer.name }
    var subtitle: String? { retailer.category.label }
}

/// A single point of interest: the way out of a zone, or a navigation destination.
final class MarkerAnnotation: NSObject, MKAnnotation {
    enum Style { case exit, destination }

    let style: Style
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(_ style: Style, coordinate: Coordinate, title: String) {
        self.style = style
        self.coordinate = coordinate.cl
        self.title = title
    }
}

/// Every no-smoking polygon of one reliability level, drawn as a single overlay.
final class ZoneOverlay: MKMultiPolygon {
    var isOfficial = true
}

enum ZoneShapes {
    /// MapKit polygons for a zone. Point zones (a bus stop and its 11 m) become small circles.
    static func polygons(for zone: NoSmokingZone) -> [MKPolygon] {
        switch zone.geometry {
        case .point(let centre):
            let ring = (0..<16).map { i in Geo.offset(centre, meters: zone.buffer, bearing: Double(i) * 22.5).cl }
            return [MKPolygon(coordinates: ring, count: ring.count)]
        case .polygons(let polygons):
            return polygons.map { polygon in
                let outer = polygon.outerRing.map(\.cl)
                let holes = polygon.rings.dropFirst().map { ring -> MKPolygon in
                    let points = ring.map(\.cl)
                    return MKPolygon(coordinates: points, count: points.count)
                }
                return MKPolygon(coordinates: outer, count: outer.count, interiorPolygons: Array(holes))
            }
        }
    }
}
