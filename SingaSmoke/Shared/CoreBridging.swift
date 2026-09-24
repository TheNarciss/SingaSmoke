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
    var color: Color { self == .official ? .green : .orange }
    var symbol: String { self == .official ? "checkmark.seal.fill" : "exclamationmark.bubble.fill" }
    var explanation: String {
        switch self {
        case .official: return "Publié par l'organisme responsable."
        case .indicative: return "Ajouté par des contributeurs OpenStreetMap : une piste, pas une garantie."
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
    /// Map glyph: a checkmark for official spots, an aeroplane at Changi, a question mark for OSM.
    var glyph: String {
        switch source {
        case .nea: return "checkmark"
        case .changi: return "airplane"
        case .osmArea, .osmVenue: return "questionmark"
        }
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
    static let fine = "Amende : 200 S$ sur le champ, jusqu'à 1 000 S$ au tribunal."
    static let signage = "Fie-toi toujours à la signalétique sur place : panneaux et marquage jaune au sol."
    static let unmapped = "Aucune carte ne montre l'intérieur des bâtiments, les passages couverts, les passerelles, les halls et void decks HDB ni les 5 m autour des entrées : fumer y est interdit aussi."
    static let vape = "Tabac : 21 ans minimum. Vapes et e-cigarettes sont illégales à Singapour, même en possession."
}
