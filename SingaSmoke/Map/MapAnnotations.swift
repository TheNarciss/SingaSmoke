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

/// How much of the no-smoking map is drawn, by zoom: the whole island in red would say nothing.
enum ZoneDetail: Hashable {
    /// Whole island: the Orchard zone and the NParks parks, as soft fills without outlines.
    case island
    /// A district: the large places (parks, schools, hospitals…), thin outlines.
    case district
    /// A few streets: everything, down to bus stops and playgrounds.
    case street

    init(latitudeDelta: Double) {
        self = latitudeDelta >= 0.1 ? .island : latitudeDelta >= 0.03 ? .district : .street
    }

    func shows(_ zone: NoSmokingZone) -> Bool {
        switch self {
        case .island: return zone.kind == .nsz || (zone.kind == .park && zone.source == .nparks)
        case .district: return zone.kind.isLarge
        case .street: return true
        }
    }
}

/// Every no-smoking polygon of one reliability level, drawn as a single overlay.
final class ZoneOverlay: MKMultiPolygon {
    var isOfficial = true
    var detail = ZoneDetail.street
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
