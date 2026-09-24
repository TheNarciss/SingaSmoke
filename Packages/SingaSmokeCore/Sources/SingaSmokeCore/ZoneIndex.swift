import Foundation

/// A uniform grid over Singapore so a GPS fix is only tested against the few zones around it,
/// not the ~15,000 on the island. Each zone is filed under every cell its buffered box touches.
public struct ZoneIndex: Sendable {
    public let zones: [NoSmokingZone]
    private let cellSize: Double
    private let cells: [Int64: [Int]]

    /// `cellSize` in degrees; 0.005° is about 550 m.
    public init(zones: [NoSmokingZone], cellSize: Double = 0.005) {
        self.zones = zones
        self.cellSize = cellSize
        var cells: [Int64: [Int]] = [:]
        for (i, zone) in zones.enumerated() {
            let box = zone.bbox.expanded(byMeters: zone.buffer)
            for key in ZoneIndex.keys(covering: box, cellSize: cellSize) {
                cells[key, default: []].append(i)
            }
        }
        self.cells = cells
    }

    private static func cell(_ value: Double, _ size: Double) -> Int64 { Int64((value / size).rounded(.down)) }

    private static func keys(covering box: BoundingBox, cellSize: Double) -> [Int64] {
        let x0 = cell(box.minLongitude, cellSize), x1 = cell(box.maxLongitude, cellSize)
        let y0 = cell(box.minLatitude, cellSize), y1 = cell(box.maxLatitude, cellSize)
        guard x1 - x0 < 400, y1 - y0 < 400 else { return [] }   // a malformed giant: ignore
        var keys: [Int64] = []
        keys.reserveCapacity(Int((x1 - x0 + 1) * (y1 - y0 + 1)))
        for x in x0...x1 { for y in y0...y1 { keys.append(x &* 1_000_003 &+ y) } }
        return keys
    }

    /// Zones whose buffered box could reach within `radius` metres of `p`. A superset: callers
    /// measure. Returned in index order, so results are deterministic.
    public func candidates(near p: Coordinate, radius: Double = 0) -> [NoSmokingZone] {
        let box = BoundingBox(minLatitude: p.latitude, maxLatitude: p.latitude,
                              minLongitude: p.longitude, maxLongitude: p.longitude).expanded(byMeters: radius)
        var seen = Set<Int>()
        var result: [Int] = []
        for key in ZoneIndex.keys(covering: box, cellSize: cellSize) {
            for i in cells[key] ?? [] where seen.insert(i).inserted { result.append(i) }
        }
        return result.sorted().map { zones[$0] }
    }

    /// Every zone within `radius` metres of `p` (inside ones have a negative distance), nearest first.
    public func zones(near p: Coordinate, radius: Double) -> [(zone: NoSmokingZone, signedDistance: Double)] {
        candidates(near: p, radius: radius)
            .map { ($0, $0.signedDistance(to: p)) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
    }

    /// The zones that contain `p`.
    public func zones(containing p: Coordinate) -> [NoSmokingZone] {
        zones(near: p, radius: 0).map(\.zone)
    }

    /// Zones intersecting a map rectangle, for drawing.
    public func zones(in box: BoundingBox) -> [NoSmokingZone] {
        var seen = Set<Int>()
        var result: [Int] = []
        for key in ZoneIndex.keys(covering: box, cellSize: cellSize) {
            for i in cells[key] ?? [] where seen.insert(i).inserted { result.append(i) }
        }
        return result.sorted().map { zones[$0] }
    }
}
