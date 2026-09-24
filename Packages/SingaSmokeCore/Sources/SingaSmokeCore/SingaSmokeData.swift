import Foundation

/// Everything the app ships with, decoded and indexed.
public struct SingaSmokeData: Sendable {
    public let spots: [SmokingSpot]
    public let zones: [NoSmokingZone]
    public let retailers: [Retailer]
    public let meta: DataMeta?
    public let zoneIndex: ZoneIndex

    public init(spots: [SmokingSpot], zones: [NoSmokingZone], retailers: [Retailer], meta: DataMeta?) {
        self.spots = spots
        self.zones = zones
        self.retailers = retailers
        self.meta = meta
        zoneIndex = ZoneIndex(zones: zones)
    }

    public enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        public var description: String {
            switch self {
            case .missing(let file): return "Missing data file: \(file)"
            }
        }
    }

    /// Reads spots.geojson, zones.geojson, retailers.geojson and meta.json from `directory`.
    public static func load(from directory: URL) throws -> SingaSmokeData {
        func read(_ name: String) throws -> Data {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { throw LoadError.missing(name) }
            return data
        }
        let spots = try GeoJSONDecoding.spots(from: read("spots.geojson"))
        let zones = try GeoJSONDecoding.zones(from: read("zones.geojson"))
        let retailers = try GeoJSONDecoding.retailers(from: read("retailers.geojson"))
        let meta = try? JSONDecoder().decode(DataMeta.self, from: read("meta.json"))
        return SingaSmokeData(spots: spots, zones: zones, retailers: retailers, meta: meta)
    }

    public func verdict(for fix: GPSFix?) -> Verdict {
        VerdictEngine.evaluate(fix: fix, spots: spots, index: zoneIndex)
    }

    /// Nearest spots for the banner's suggestion: not airside (needs a boarding pass).
    public func nearestReachableSpot(to p: Coordinate) -> RankedPlace<SmokingSpot>? {
        Ranking.nearest(spots.filter { !$0.isAirside }, to: p, limit: 1).first
    }
}
