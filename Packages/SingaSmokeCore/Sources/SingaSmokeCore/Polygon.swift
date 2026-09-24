import Foundation

/// A polygon as GeoJSON describes it: an outer ring, then zero or more holes.
/// Rings may or may not repeat their first point at the end; both are handled.
public struct Polygon: Sendable {
    public let rings: [[Coordinate]]
    public let bbox: BoundingBox

    public init?(rings: [[Coordinate]]) {
        let usable = rings.filter { $0.count >= 3 }
        guard let outer = usable.first, let box = BoundingBox(outer) else { return nil }
        self.rings = usable
        self.bbox = box
    }

    public var outerRing: [Coordinate] { rings[0] }

    /// Ray casting on the outer ring, minus the holes. Degrees are fine for containment:
    /// the test only compares positions, it never measures.
    public func contains(_ p: Coordinate) -> Bool {
        guard bbox.contains(p), Polygon.ringContains(outerRing, p) else { return false }
        for hole in rings.dropFirst() where Polygon.ringContains(hole, p) { return false }
        return true
    }

    static func ringContains(_ ring: [Coordinate], _ p: Coordinate) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.latitude > p.latitude) != (b.latitude > p.latitude) {
                let crossing = (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if p.longitude < crossing { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Distance in metres from `p` to the nearest edge of any ring, and the point on that edge.
    public func nearestBoundaryPoint(to p: Coordinate) -> (point: Coordinate, distance: Double) {
        let projection = LocalProjection(origin: p)
        var best = (point: p, distance: Double.infinity)
        for ring in rings {
            guard ring.count >= 2 else { continue }
            var previous = projection.project(ring[ring.count - 1])
            for vertex in ring {
                let current = projection.project(vertex)
                let (x, y) = Polygon.closestPointOnSegment(px: 0, py: 0, ax: previous.x, ay: previous.y, bx: current.x, by: current.y)
                let d = (x * x + y * y).squareRoot()
                if d < best.distance { best = (projection.unproject(x: x, y: y), d) }
                previous = current
            }
        }
        return best
    }

    public func distanceToBoundary(from p: Coordinate) -> Double {
        nearestBoundaryPoint(to: p).distance
    }

    static func closestPointOnSegment(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double) -> (Double, Double) {
        let dx = bx - ax, dy = by - ay
        let length2 = dx * dx + dy * dy
        guard length2 > 0 else { return (ax, ay) }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length2))
        return (ax + t * dx, ay + t * dy)
    }
}
