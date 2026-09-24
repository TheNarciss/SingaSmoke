import Foundation

/// Just enough GeoJSON to read the files `scripts/build.mjs` writes.
struct FeatureCollection<Properties: Decodable>: Decodable {
    let features: [Feature<Properties>]
}

struct Feature<Properties: Decodable>: Decodable {
    let id: String
    let geometry: GeoJSONGeometry
    let properties: Properties

    private enum CodingKeys: String, CodingKey { case id, geometry, properties }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? c.decode(String.self, forKey: .id) {
            id = text
        } else if let number = try? c.decode(Int.self, forKey: .id) {
            id = String(number)
        } else {
            id = UUID().uuidString
        }
        geometry = try c.decode(GeoJSONGeometry.self, forKey: .geometry)
        properties = try c.decode(Properties.self, forKey: .properties)
    }
}

enum GeoJSONGeometry: Decodable {
    case point(Coordinate)
    case polygon([[Coordinate]])
    case multiPolygon([[[Coordinate]]])
    case unsupported

    private enum CodingKeys: String, CodingKey { case type, coordinates }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "Point":
            let pair = try c.decode([Double].self, forKey: .coordinates)
            guard let coordinate = Coordinate(geoJSON: pair) else { self = .unsupported; return }
            self = .point(coordinate)
        case "Polygon":
            let rings = try c.decode([[[Double]]].self, forKey: .coordinates)
            self = .polygon(rings.map { $0.compactMap(Coordinate.init(geoJSON:)) })
        case "MultiPolygon":
            let polygons = try c.decode([[[[Double]]]].self, forKey: .coordinates)
            self = .multiPolygon(polygons.map { $0.map { $0.compactMap(Coordinate.init(geoJSON:)) } })
        default:
            self = .unsupported
        }
    }

    var pointCoordinate: Coordinate? {
        if case .point(let c) = self { return c }
        return nil
    }
}

// MARK: - Property payloads

struct SpotProperties: Decodable {
    let name: String
    let details: String?
    let source: String
    let approx: Bool?
    let approxRadius: Double?
    let photo: String?
    let level: String?
    let airside: Bool?
    let hours: String?
    let venueKind: String?
    let url: String?
    let updated: String?
}

struct ZoneProperties: Decodable {
    let kind: String
    let name: String?
    let source: String
    let buffer: Double?
}

struct RetailerProperties: Decodable {
    let name: String
    let licensee: String?
    let address: String
    let postal: String
    let category: String
    let brand: String?
    let building: String?
    let validity: String?
}

// MARK: - Decoding into the model

enum GeoJSONDecoding {
    static func spots(from data: Data) throws -> [SmokingSpot] {
        let collection = try JSONDecoder().decode(FeatureCollection<SpotProperties>.self, from: data)
        return collection.features.compactMap { f in
            guard let coordinate = f.geometry.pointCoordinate,
                  let source = SpotSource(rawValue: f.properties.source) else { return nil }
            let p = f.properties
            return SmokingSpot(
                id: f.id, name: p.name, details: p.details ?? "", coordinate: coordinate, source: source,
                isApproximate: p.approx ?? false, approximateRadius: p.approxRadius,
                photoURL: p.photo.flatMap(URL.init(string:)), level: p.level, isAirside: p.airside ?? false,
                openingHours: p.hours, venueKind: p.venueKind, sourceURL: p.url.flatMap(URL.init(string:)),
                updated: p.updated
            )
        }
    }

    static func zones(from data: Data) throws -> [NoSmokingZone] {
        let collection = try JSONDecoder().decode(FeatureCollection<ZoneProperties>.self, from: data)
        return collection.features.compactMap { f in
            let p = f.properties
            let geometry: ZoneGeometry
            switch f.geometry {
            case .point(let c):
                geometry = .point(c)
            case .polygon(let rings):
                guard let polygon = Polygon(rings: rings) else { return nil }
                geometry = .polygons([polygon])
            case .multiPolygon(let polygons):
                let parts = polygons.compactMap(Polygon.init(rings:))
                guard !parts.isEmpty else { return nil }
                geometry = .polygons(parts)
            case .unsupported:
                return nil
            }
            return NoSmokingZone(
                id: f.id, kind: ZoneKind(rawValue: p.kind) ?? .other, name: p.name,
                source: ZoneSource(rawValue: p.source) ?? .osm, buffer: p.buffer ?? 0, geometry: geometry
            )
        }
    }

    static func retailers(from data: Data) throws -> [Retailer] {
        let collection = try JSONDecoder().decode(FeatureCollection<RetailerProperties>.self, from: data)
        return collection.features.compactMap { f in
            guard let coordinate = f.geometry.pointCoordinate else { return nil }
            let p = f.properties
            return Retailer(
                id: f.id, name: p.name, licensee: p.licensee, address: p.address, postalCode: p.postal,
                category: RetailCategory(rawValue: p.category) ?? .other, brand: p.brand,
                building: p.building, validity: p.validity, coordinate: coordinate
            )
        }
    }
}
