import XCTest
@testable import SingaSmokeCore

final class GeoTests: XCTestCase {
    func testDistanceToItselfIsZero() {
        let p = Coordinate(latitude: 1.3521, longitude: 103.8198)
        XCTAssertEqual(Geo.distance(p, p), 0, accuracy: 1e-9)
    }

    func testDistanceIsSymmetric() {
        let a = Coordinate(latitude: 1.28393, longitude: 103.85144)
        let b = Coordinate(latitude: 1.35461, longitude: 103.98508)
        XCTAssertEqual(Geo.distance(a, b), Geo.distance(b, a), accuracy: 1e-6)
    }

    func testOneDegreeOfLatitude() {
        // π/180 × 6,371,008.8 m
        let d = Geo.distance(Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 1, longitude: 0))
        XCTAssertEqual(d, 111_195.08, accuracy: 0.5)
    }

    func testOneDegreeOfLongitudeShrinksWithLatitude() {
        let atEquator = Geo.distance(Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 1))
        let atSixty = Geo.distance(Coordinate(latitude: 60, longitude: 0), Coordinate(latitude: 60, longitude: 1))
        XCTAssertEqual(atSixty / atEquator, 0.5, accuracy: 0.001)
    }

    func testRafflesPlaceToChangiTerminal3() {
        // Straight line across the island: ~16.8 km.
        let raffles = Coordinate(latitude: 1.28393, longitude: 103.85144)
        let changiT3 = Coordinate(latitude: 1.35461, longitude: 103.98508)
        XCTAssertEqual(Geo.distance(raffles, changiT3), 16_807, accuracy: 60)
    }

    func testHaversineAgreesWithLocalProjectionAtStreetScale() {
        let p = Fixtures.origin
        let projection = LocalProjection(origin: p)
        for (x, y) in [(300.0, 0.0), (0.0, 250.0), (-120.0, 80.0), (700.0, -900.0)] {
            let q = projection.unproject(x: x, y: y)
            XCTAssertEqual(Geo.distance(p, q), (x * x + y * y).squareRoot(), accuracy: 0.5)
            let back = projection.project(q)
            XCTAssertEqual(back.x, x, accuracy: 1e-6)
            XCTAssertEqual(back.y, y, accuracy: 1e-6)
        }
    }

    func testBearingsAtTheCardinalPoints() {
        let p = Fixtures.origin
        XCTAssertEqual(Geo.bearing(from: p, to: Fixtures.at(0, 100)), 0, accuracy: 0.01)
        XCTAssertEqual(Geo.bearing(from: p, to: Fixtures.at(100, 0)), 90, accuracy: 0.01)
        XCTAssertEqual(Geo.bearing(from: p, to: Fixtures.at(0, -100)), 180, accuracy: 0.01)
        XCTAssertEqual(Geo.bearing(from: p, to: Fixtures.at(-100, 0)), 270, accuracy: 0.01)
    }

    func testOffsetTravelsTheRequestedDistance() {
        let p = Fixtures.origin
        for bearing in stride(from: 0.0, to: 360, by: 30) {
            let q = Geo.offset(p, meters: 150, bearing: bearing)
            XCTAssertEqual(Geo.distance(p, q), 150, accuracy: 0.2)
            XCTAssertEqual(Geo.bearing(from: p, to: q), bearing, accuracy: 0.1)
        }
    }

    func testCompassDirection() {
        XCTAssertEqual(CompassDirection(bearing: 0), .north)
        XCTAssertEqual(CompassDirection(bearing: 22), .north)
        XCTAssertEqual(CompassDirection(bearing: 23), .northEast)
        XCTAssertEqual(CompassDirection(bearing: 90), .east)
        XCTAssertEqual(CompassDirection(bearing: 181), .south)
        XCTAssertEqual(CompassDirection(bearing: 359), .north)
        XCTAssertEqual(CompassDirection(bearing: -45), .northWest)
        XCTAssertEqual(CompassDirection(bearing: 720 + 270), .west)
        XCTAssertEqual(CompassDirection.east.towards, "vers l'est")
        XCTAssertEqual(CompassDirection.southWest.towards, "vers le sud-ouest")
    }

    func testBoundingBoxExpansion() {
        let box = BoundingBox(Fixtures.rect(x0: 0, y0: 0, x1: 100, y1: 100))!
        let grown = box.expanded(byMeters: 50)
        XCTAssertTrue(grown.contains(Fixtures.at(-40, -40)))
        XCTAssertTrue(grown.contains(Fixtures.at(140, 140)))
        XCTAssertFalse(grown.contains(Fixtures.at(-60, 50)))
        XCTAssertFalse(box.contains(Fixtures.at(-10, 50)))
    }

    func testSingaporeBounds() {
        XCTAssertTrue(Geo.singapore.contains(Coordinate(latitude: 1.3521, longitude: 103.8198)))
        XCTAssertFalse(Geo.singapore.contains(Coordinate(latitude: 48.8566, longitude: 2.3522)))   // Paris
    }
}
