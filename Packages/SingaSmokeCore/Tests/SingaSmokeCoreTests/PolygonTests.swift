import XCTest
@testable import SingaSmokeCore

final class PolygonTests: XCTestCase {
    private let square = Polygon(rings: [Fixtures.rect(x0: 0, y0: 0, x1: 100, y1: 100)])!

    func testContainsItsInterior() {
        XCTAssertTrue(square.contains(Fixtures.at(50, 50)))
        XCTAssertTrue(square.contains(Fixtures.at(1, 99)))
        XCTAssertTrue(square.contains(Fixtures.at(99, 1)))
    }

    func testExcludesTheOutside() {
        XCTAssertFalse(square.contains(Fixtures.at(-1, 50)))
        XCTAssertFalse(square.contains(Fixtures.at(101, 50)))
        XCTAssertFalse(square.contains(Fixtures.at(50, 101)))
        XCTAssertFalse(square.contains(Fixtures.at(50, -1)))
        XCTAssertFalse(square.contains(Fixtures.at(500, 500)))
    }

    func testHoleIsExcluded() {
        let donut = Polygon(rings: [
            Fixtures.rect(x0: 0, y0: 0, x1: 100, y1: 100),
            Fixtures.rect(x0: 40, y0: 40, x1: 60, y1: 60),
        ])!
        XCTAssertFalse(donut.contains(Fixtures.at(50, 50)), "inside the hole")
        XCTAssertTrue(donut.contains(Fixtures.at(20, 20)), "in the ring around the hole")
        XCTAssertTrue(donut.contains(Fixtures.at(70, 50)))
    }

    func testConcaveShape() {
        // An L: the square minus its top-right quarter.
        let l = Polygon(rings: [[
            Fixtures.at(0, 0), Fixtures.at(100, 0), Fixtures.at(100, 50),
            Fixtures.at(50, 50), Fixtures.at(50, 100), Fixtures.at(0, 100), Fixtures.at(0, 0),
        ]])!
        XCTAssertTrue(l.contains(Fixtures.at(25, 75)))
        XCTAssertTrue(l.contains(Fixtures.at(75, 25)))
        XCTAssertFalse(l.contains(Fixtures.at(75, 75)), "in the notch")
    }

    func testOpenAndClosedRingsAgree() {
        let closed = Fixtures.rect(x0: 0, y0: 0, x1: 100, y1: 100)
        let open = Polygon(rings: [Array(closed.dropLast())])!
        for (x, y) in [(50.0, 50.0), (-5.0, 50.0), (99.0, 99.0), (101.0, 1.0)] {
            XCTAssertEqual(open.contains(Fixtures.at(x, y)), square.contains(Fixtures.at(x, y)))
        }
    }

    func testDegenerateRingIsRejected() {
        XCTAssertNil(Polygon(rings: [[Fixtures.at(0, 0), Fixtures.at(10, 0)]]))
        XCTAssertNil(Polygon(rings: []))
    }

    func testDistanceToBoundaryFromOutside() {
        XCTAssertEqual(square.distanceToBoundary(from: Fixtures.at(150, 50)), 50, accuracy: 0.1)
        XCTAssertEqual(square.distanceToBoundary(from: Fixtures.at(50, -30)), 30, accuracy: 0.1)
        // Diagonal from the corner.
        XCTAssertEqual(square.distanceToBoundary(from: Fixtures.at(130, 140)), 50, accuracy: 0.1)
    }

    func testDistanceToBoundaryFromInside() {
        XCTAssertEqual(square.distanceToBoundary(from: Fixtures.at(50, 50)), 50, accuracy: 0.1)
        XCTAssertEqual(square.distanceToBoundary(from: Fixtures.at(10, 50)), 10, accuracy: 0.1)
    }

    func testDistanceCountsHoleEdges() {
        let donut = Polygon(rings: [
            Fixtures.rect(x0: 0, y0: 0, x1: 100, y1: 100),
            Fixtures.rect(x0: 40, y0: 40, x1: 60, y1: 60),
        ])!
        XCTAssertEqual(donut.distanceToBoundary(from: Fixtures.at(35, 50)), 5, accuracy: 0.1)
    }

    func testNearestBoundaryPointLiesOnTheEdge() {
        let nearest = square.nearestBoundaryPoint(to: Fixtures.at(150, 30))
        let local = Fixtures.projection.project(nearest.point)
        XCTAssertEqual(local.x, 100, accuracy: 0.1)
        XCTAssertEqual(local.y, 30, accuracy: 0.1)
        XCTAssertEqual(nearest.distance, 50, accuracy: 0.1)
    }

    func testBoundingBox() {
        XCTAssertTrue(square.bbox.contains(Fixtures.at(0, 0)))
        XCTAssertTrue(square.bbox.contains(Fixtures.at(100, 100)))
        XCTAssertFalse(square.bbox.contains(Fixtures.at(101, 100)))
    }
}
