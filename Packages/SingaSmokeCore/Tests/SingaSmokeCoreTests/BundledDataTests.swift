import XCTest
@testable import SingaSmokeCore

/// Runs the logic against the data the app actually ships (SingaSmoke/Resources/Data).
final class BundledDataTests: XCTestCase {
    private static var cached: SingaSmokeData?

    private func data() throws -> SingaSmokeData {
        if let cached = Self.cached { return cached }
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SingaSmokeCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // SingaSmokeCore
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("SingaSmoke/Resources/Data")
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("zones.geojson").path) else {
            throw XCTSkip("no generated data at \(directory.path): run `npm run data`")
        }
        let loaded = try SingaSmokeData.load(from: directory)
        Self.cached = loaded
        return loaded
    }

    private func kinds(in d: SingaSmokeData, at latitude: Double, _ longitude: Double) -> Set<ZoneKind> {
        Set(d.zoneIndex.zones(containing: Coordinate(latitude: latitude, longitude: longitude)).map(\.kind))
    }

    func testVolumes() throws {
        let d = try data()
        XCTAssertGreaterThanOrEqual(d.spots.filter { $0.source == .nea }.count, 40)
        XCTAssertGreaterThanOrEqual(d.spots.filter { $0.source == .changi }.count, 20)
        XCTAssertGreaterThanOrEqual(d.zones.count, 5_000)
        XCTAssertGreaterThanOrEqual(d.retailers.count, 3_000)
        XCTAssertNotNil(d.meta)
    }

    func testOrchardRoadIsANoSmokingZone() throws {
        let d = try data()
        XCTAssertTrue(kinds(in: d, at: 1.30390, 103.83170).contains(.nsz), "ION Orchard")
        XCTAssertTrue(kinds(in: d, at: 1.30280, 103.83480).contains(.nsz), "Ngee Ann City")
    }

    func testParks() throws {
        let d = try data()
        XCTAssertTrue(kinds(in: d, at: 1.31380, 103.81590).contains(.park), "Singapore Botanic Gardens")
        XCTAssertTrue(kinds(in: d, at: 1.30100, 103.91200).contains(.park), "East Coast Park")
        XCTAssertTrue(kinds(in: d, at: 1.36230, 103.84680).contains(.park), "Bishan-Ang Mo Kio Park")
    }

    func testRafflesPlaceIsNeitherOrchardNorAPark() throws {
        let found = kinds(in: try data(), at: 1.28400, 103.85150)
        XCTAssertFalse(found.contains(.nsz))
        XCTAssertFalse(found.contains(.park))
    }

    func testEveryYellowBoxIsInsideOrchardAndReadsAsAllowed() throws {
        let d = try data()
        let nsz = d.zones.filter { $0.kind == .nsz }
        for spot in d.spots where spot.source == .nea {
            XCTAssertTrue(nsz.contains { $0.contains(spot.coordinate) }, "\(spot.name) is outside the Orchard zone")
            guard case .atSpot(let found, _, _) = d.verdict(for: GPSFix(coordinate: spot.coordinate, horizontalAccuracy: 5)) else {
                XCTFail("standing on \(spot.name) should read as allowed")
                continue
            }
            XCTAssertEqual(found.source, .nea)
        }
    }

    func testOrchardAwayFromTheBoxesIsProhibited() throws {
        let d = try data()
        // Middle of Orchard Road, in front of Ngee Ann City.
        let fix = GPSFix(coordinate: Coordinate(latitude: 1.30305, longitude: 103.83420), horizontalAccuracy: 5)
        switch d.verdict(for: fix) {
        case .prohibited(let hit, let others, _):
            XCTAssertTrue(([hit] + others).contains { $0.zone.kind == .nsz })
        case .atSpot(let spot, _, _):
            XCTAssertEqual(spot.source, .nea, "only a yellow box may override the Orchard zone")
        default:
            XCTFail("Orchard Road must not read as clear")
        }
    }

    func testChangiPinsAreApproximateAndOnTheAirport() throws {
        let d = try data()
        for spot in d.spots where spot.source == .changi {
            XCTAssertTrue(spot.isApproximate)
            XCTAssertNotNil(spot.approximateRadius)
            XCTAssertTrue((1.32...1.38).contains(spot.coordinate.latitude) && (103.97...104.01).contains(spot.coordinate.longitude))
        }
    }

    func testEverythingIsInSingapore() throws {
        let d = try data()
        XCTAssertTrue(d.spots.allSatisfy { Geo.singapore.contains($0.coordinate) })
        XCTAssertTrue(d.retailers.allSatisfy { Geo.singapore.contains($0.coordinate) })
    }

    func testEveryRetailerCategoryIsRepresented() throws {
        let d = try data()
        let present = Set(d.retailers.map(\.category))
        XCTAssertEqual(present, Set(RetailCategory.allCases))
    }

    func testVerdictIsFastEnoughForEveryGPSUpdate() throws {
        let d = try data()
        var generator = SeededGenerator(seed: 7)
        let start = Date()
        for _ in 0..<2_000 {
            let p = Coordinate(latitude: .random(in: 1.27...1.44, using: &generator),
                               longitude: .random(in: 103.65...103.98, using: &generator))
            _ = d.verdict(for: GPSFix(coordinate: p, horizontalAccuracy: 15))
        }
        // Debug build, on CI hardware: a generous bound that still catches an accidental O(n) scan.
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }
}
