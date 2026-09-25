import CoreLocation
import MapKit
import SingaSmokeCore
import SwiftUI

extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }
}

extension BoundingBox {
    /// The visible rectangle of a map region, grown by `padding` (a fraction of the span).
    init(_ region: MKCoordinateRegion, padding: Double = 0.1) {
        let dLat = region.span.latitudeDelta * (0.5 + padding)
        let dLon = region.span.longitudeDelta * (0.5 + padding)
        self.init(minLatitude: region.center.latitude - dLat, maxLatitude: region.center.latitude + dLat,
                  minLongitude: region.center.longitude - dLon, maxLongitude: region.center.longitude + dLon)
    }
}

extension Reliability {
    var color: Color { self == .official ? Brand.allowed : Brand.warning }
    var symbol: String { self == .official ? "checkmark.seal.fill" : "exclamationmark.bubble.fill" }
    var explanation: String {
        switch self {
        case .official: return "Published by the agency in charge."
        case .indicative: return "Added by OpenStreetMap contributors: a lead, not a guarantee."
        }
    }
}

extension ZoneKind {
    var symbol: String {
        switch self {
        case .nsz: return "nosign"
        case .park: return "tree.fill"
        case .beach: return "beach.umbrella.fill"
        case .reservoir: return "drop.fill"
        case .playground: return "figure.play"
        case .fitness: return "figure.strengthtraining.traditional"
        case .court: return "sportscourt.fill"
        case .busStop: return "bus.fill"
        case .busInterchange: return "bus.doubledecker.fill"
        case .hospital: return "cross.case.fill"
        case .school: return "graduationcap.fill"
        case .hawker: return "fork.knife"
        case .stadium: return "sportscourt"
        case .sportsCentre: return "figure.pool.swim"
        case .carPark: return "parkingsign"
        case .ferryTerminal: return "ferry.fill"
        case .other: return "nosign"
        }
    }
}

extension SmokingSpot {
    /// Same symbols as the map markers: the painted box for NEA, a plane at Changi, a dashed box for OSM.
    var glyph: String {
        switch source {
        case .nea: return "square"
        case .changi: return "airplane"
        case .osmArea, .osmVenue: return "square.dashed"
        }
    }

    var tint: Color { reliability == .official ? Brand.allowed : Brand.allowed.opacity(0.7) }

    /// The one thing worth flagging about a spot, if any.
    var caveat: String? {
        if isAirside { return "Transit area" }
        if isApproximate { return "Approximate" }
        if reliability == .indicative { return "Indicative" }
        return nil
    }
}

extension RetailCategory {
    var symbol: String {
        switch self {
        case .convenience: return "cart.fill"
        case .supermarket: return "basket.fill"
        case .minimart: return "bag.fill"
        case .petrol: return "fuelpump.fill"
        case .kopitiam: return "cup.and.saucer.fill"
        case .other: return "storefront.fill"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .convenience: return .systemBlue
        case .supermarket: return .systemIndigo
        case .minimart: return .systemTeal
        case .petrol: return .systemOrange
        case .kopitiam: return .systemBrown
        case .other: return .systemGray
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

enum Legal {
    static let fine = "Fine: S$200 on the spot, up to S$1,000 if it goes to court."
    static let signage = "Always go by the signs on site: notices and yellow markings on the ground."
    static let unmapped = "No map shows building interiors, covered walkways, overhead bridges, HDB lift lobbies and void decks, or the 5 m around entrances: smoking is banned there too."
    static let vape = "Tobacco is 21+. Vapes and e-cigarettes are illegal in Singapore, even to possess."
}
