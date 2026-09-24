import Foundation

// MARK: - Reliability

/// How much a piece of data can be trusted, shown next to every spot and zone.
public enum Reliability: String, Sendable {
    /// Published by the agency in charge (NEA, NParks, HSA, Changi Airport Group).
    case official
    /// Mapped by OpenStreetMap contributors: a lead, not a promise.
    case indicative

    public var label: String {
        switch self {
        case .official: return "Officiel"
        case .indicative: return "Indicatif"
        }
    }
}

// MARK: - Smoking spots

public enum SpotSource: String, Sendable, CaseIterable {
    case nea
    case changi
    case osmArea = "osm_area"
    case osmVenue = "osm_venue"

    public var reliability: Reliability {
        switch self {
        case .nea, .changi: return .official
        case .osmArea, .osmVenue: return .indicative
        }
    }

    public var label: String {
        switch self {
        case .nea: return "Zone fumeur NEA"
        case .changi: return "Zone fumeur Changi Airport"
        case .osmArea: return "Espace fumeur (OpenStreetMap)"
        case .osmVenue: return "Établissement avec coin fumeur (OpenStreetMap)"
        }
    }

    public var publisher: String {
        switch self {
        case .nea: return "NEA"
        case .changi: return "Changi Airport Group"
        case .osmArea, .osmVenue: return "OpenStreetMap"
        }
    }
}

public struct SmokingSpot: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Where exactly: NEA's description, Changi's wording ("opposite Gate B10"), OSM details.
    public let details: String
    public let coordinate: Coordinate
    public let source: SpotSource
    /// True when the pin is not where the spot is (Changi: placed on a gate or the terminal).
    public let isApproximate: Bool
    /// How far the real spot may be from the pin, metres.
    public let approximateRadius: Double?
    public let photoURL: URL?
    public let level: String?
    /// Changi transit area: only reachable after immigration, with a boarding pass.
    public let isAirside: Bool
    public let openingHours: String?
    public let venueKind: String?
    public let sourceURL: URL?
    /// Last update in the source, "yyyy-mm-dd".
    public let updated: String?

    public init(id: String, name: String, details: String, coordinate: Coordinate, source: SpotSource,
                isApproximate: Bool = false, approximateRadius: Double? = nil, photoURL: URL? = nil,
                level: String? = nil, isAirside: Bool = false, openingHours: String? = nil,
                venueKind: String? = nil, sourceURL: URL? = nil, updated: String? = nil) {
        self.id = id
        self.name = name
        self.details = details
        self.coordinate = coordinate
        self.source = source
        self.isApproximate = isApproximate
        self.approximateRadius = approximateRadius
        self.photoURL = photoURL
        self.level = level
        self.isAirside = isAirside
        self.openingHours = openingHours
        self.venueKind = venueKind
        self.sourceURL = sourceURL
        self.updated = updated
    }

    public var reliability: Reliability { source.reliability }
}

// MARK: - No-smoking zones

public enum ZoneKind: String, Sendable, CaseIterable {
    case nsz
    case park
    case beach
    case reservoir
    case playground
    case fitness
    case court
    case busStop = "bus_stop"
    case busInterchange = "bus_interchange"
    case hospital
    case school
    case hawker
    case stadium
    case sportsCentre = "sports_centre"
    case carPark = "car_park"
    case ferryTerminal = "ferry_terminal"
    case other

    public var label: String {
        switch self {
        case .nsz: return "Zone non-fumeur d'Orchard Road"
        case .park: return "Parc ou jardin"
        case .beach: return "Plage"
        case .reservoir: return "Réservoir"
        case .playground: return "Aire de jeux"
        case .fitness: return "Coin fitness"
        case .court: return "Terrain de sport"
        case .busStop: return "Arrêt de bus"
        case .busInterchange: return "Gare routière"
        case .hospital: return "Hôpital"
        case .school: return "École, crèche ou université"
        case .hawker: return "Hawker centre ou food court"
        case .stadium: return "Stade"
        case .sportsCentre: return "Complexe sportif"
        case .carPark: return "Parking à étages"
        case .ferryTerminal: return "Terminal de ferry"
        case .other: return "Lieu non-fumeur"
        }
    }

    /// The rule, in one line, as the regulations put it.
    public var rule: String {
        switch self {
        case .nsz: return "Interdit partout dans la zone, sauf dans les carrés jaunes (DSA)."
        case .park: return "Parcs et jardins : 100 % non-fumeur."
        case .beach: return "Plages récréatives (East Coast, Changi, Sentosa…) : non-fumeur."
        case .reservoir: return "Réservoir : non-fumeur."
        case .playground: return "Aires de jeux et leurs abords : interdit."
        case .fitness: return "Coins fitness et leurs abords : interdit."
        case .court: return "Terrains de sport (basket, badminton, tennis…) : interdit."
        case .busStop: return "Interdit à moins de 5 m d'un abri ou poteau de bus."
        case .busInterchange: return "Gares routières : interdit."
        case .hospital: return "Tout le terrain de l'hôpital, parkings compris."
        case .school: return "Interdit dans l'enceinte et à moins de 5 m de la clôture."
        case .hawker: return "Interdit partout, sauf coin fumeur marqué en jaune."
        case .stadium: return "Stades et leurs abords : interdit."
        case .sportsCentre: return "Complexes sportifs et piscines : interdit."
        case .carPark: return "Parkings à étages : lieu couvert, interdit."
        case .ferryTerminal: return "Terminaux de ferry : interdit."
        case .other: return "Lieu non-fumeur."
        }
    }

    /// Drawn on the map at every zoom (large areas) or only when zoomed in (small ones).
    public var isLarge: Bool {
        switch self {
        case .nsz, .park, .beach, .reservoir, .hospital, .school, .stadium, .busInterchange: return true
        default: return false
        }
    }
}

public enum ZoneSource: String, Sendable {
    case nea
    case nparks
    case osm

    public var reliability: Reliability { self == .osm ? .indicative : .official }

    public var publisher: String {
        switch self {
        case .nea: return "NEA"
        case .nparks: return "NParks"
        case .osm: return "OpenStreetMap"
        }
    }
}

public enum ZoneGeometry: Sendable {
    case point(Coordinate)
    case polygons([Polygon])
}

/// A place where smoking is prohibited: its geometry grown by `buffer` metres.
/// A bus stop is a point with an 11 m radius; a school is its compound plus 5 m.
public struct NoSmokingZone: Identifiable, Sendable {
    public let id: String
    public let kind: ZoneKind
    public let name: String?
    public let source: ZoneSource
    public let buffer: Double
    public let geometry: ZoneGeometry
    /// Bounding box of the geometry, not including the buffer.
    public let bbox: BoundingBox

    public init(id: String, kind: ZoneKind, name: String?, source: ZoneSource, buffer: Double, geometry: ZoneGeometry) {
        self.id = id
        self.kind = kind
        self.name = name
        self.source = source
        self.buffer = max(0, buffer)
        self.geometry = geometry
        switch geometry {
        case .point(let c):
            bbox = BoundingBox(minLatitude: c.latitude, maxLatitude: c.latitude, minLongitude: c.longitude, maxLongitude: c.longitude)
        case .polygons(let polygons):
            var box = polygons.first?.bbox ?? BoundingBox(minLatitude: 0, maxLatitude: 0, minLongitude: 0, maxLongitude: 0)
            for p in polygons.dropFirst() {
                box.include(Coordinate(latitude: p.bbox.minLatitude, longitude: p.bbox.minLongitude))
                box.include(Coordinate(latitude: p.bbox.maxLatitude, longitude: p.bbox.maxLongitude))
            }
            bbox = box
        }
    }

    public var reliability: Reliability { source.reliability }

    /// "Parc ou jardin", or the zone's own name when it has one.
    public var title: String {
        if let name, !name.isEmpty { return "\(kind.label) · \(name)" }
        return kind.label
    }

    /// Metres from `p` to the edge of the prohibited area: negative inside, positive outside.
    public func signedDistance(to p: Coordinate) -> Double {
        switch geometry {
        case .point(let center):
            return Geo.distance(center, p) - buffer
        case .polygons(let polygons):
            var inside = false
            var edge = Double.infinity
            for polygon in polygons {
                if polygon.contains(p) { inside = true }
                edge = min(edge, polygon.distanceToBoundary(from: p))
            }
            return inside ? -(edge + buffer) : edge - buffer
        }
    }

    public func contains(_ p: Coordinate) -> Bool { signedDistance(to: p) <= 0 }

    /// The nearest point just outside the prohibited area, with a small margin.
    /// For a point zone: straight away from its centre. For a polygon: past its nearest edge.
    public func exitPoint(from p: Coordinate, margin: Double = 5) -> Coordinate {
        switch geometry {
        case .point(let center):
            let away = Geo.distance(center, p) < 0.5 ? 0 : Geo.bearing(from: center, to: p)
            return Geo.offset(center, meters: buffer + margin, bearing: away)
        case .polygons(let polygons):
            // Inside: leave through the polygon we are in, not through a neighbour's edge.
            let containing = polygons.filter { $0.contains(p) }
            let insidePolygon = !containing.isEmpty
            var best: (point: Coordinate, distance: Double)?
            for polygon in insidePolygon ? containing : polygons {
                let candidate = polygon.nearestBoundaryPoint(to: p)
                if best == nil || candidate.distance < best!.distance { best = candidate }
            }
            guard let edge = best else { return p }
            let direction: Double
            if edge.distance < 0.5 {
                // Standing on the edge: head away from the polygon's centre.
                direction = Geo.bearing(from: bbox.center, to: p)
            } else {
                direction = insidePolygon ? Geo.bearing(from: p, to: edge.point) : Geo.bearing(from: edge.point, to: p)
            }
            let start = insidePolygon ? edge.point : p
            let extra = insidePolygon ? buffer + margin : max(0, buffer - edge.distance) + margin
            return Geo.offset(start, meters: extra, bearing: direction)
        }
    }
}

// MARK: - Retailers

public enum RetailCategory: String, Sendable, CaseIterable, Identifiable {
    case convenience
    case supermarket
    case minimart
    case petrol
    case kopitiam
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .convenience: return "Supérette"
        case .supermarket: return "Supermarché"
        case .minimart: return "Minimart"
        case .petrol: return "Station-service"
        case .kopitiam: return "Kopitiam & resto"
        case .other: return "Autre"
        }
    }
}

public struct Retailer: Identifiable, Hashable, Sendable {
    public let id: String
    /// Brand when recognised (7-Eleven, FairPrice…), otherwise the licensee's name.
    public let name: String
    public let licensee: String?
    public let address: String
    public let postalCode: String
    public let category: RetailCategory
    public let brand: String?
    public let building: String?
    /// Licence period as printed in the register ("01/09/2025 - 31/08/2026").
    public let validity: String?
    /// Building of the postal code: precise to the building, not to the shop.
    public let coordinate: Coordinate

    public init(id: String, name: String, licensee: String?, address: String, postalCode: String,
                category: RetailCategory, brand: String?, building: String?, validity: String?, coordinate: Coordinate) {
        self.id = id
        self.name = name
        self.licensee = licensee
        self.address = address
        self.postalCode = postalCode
        self.category = category
        self.brand = brand
        self.building = building
        self.validity = validity
        self.coordinate = coordinate
    }
}

// MARK: - Metadata

public struct DataSourceInfo: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let publisher: String?
    public let updated: String?
    public let url: String?
    public let licence: String?
}

public struct DataMeta: Codable, Sendable {
    public let generated: String
    public let sources: [DataSourceInfo]
}
