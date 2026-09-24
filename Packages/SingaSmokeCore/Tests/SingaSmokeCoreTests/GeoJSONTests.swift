import XCTest
@testable import SingaSmokeCore

final class GeoJSONTests: XCTestCase {
    func testSpots() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","id":"nea-17601","geometry":{"type":"Point","coordinates":[103.834382,1.309436]},
           "properties":{"name":"Goodwood Park Hotel","details":"Front of building","source":"nea","approx":false,
                         "photo":"https://www.nea.gov.sg/images/dsa/goodwood-park-hotel-1","updated":"2025-03-05"}},
          {"type":"Feature","id":"cag-t3","geometry":{"type":"Point","coordinates":[103.985,1.3546]},
           "properties":{"name":"Changi Airport T3","details":"Departure North — opposite Gate B10","source":"changi",
                         "approx":true,"approxRadius":80,"level":"2","airside":true}},
          {"type":"Feature","id":"weird","geometry":{"type":"Point","coordinates":[103.8,1.3]},
           "properties":{"name":"Unknown source","source":"somewhere-else"}}
        ]}
        """
        let spots = try GeoJSONDecoding.spots(from: Data(json.utf8))
        XCTAssertEqual(spots.count, 2, "an unknown source is skipped, not a crash")
        XCTAssertEqual(spots[0].coordinate.latitude, 1.309436, accuracy: 1e-9)
        XCTAssertEqual(spots[0].coordinate.longitude, 103.834382, accuracy: 1e-9, "GeoJSON is [lng, lat]")
        XCTAssertEqual(spots[0].source, .nea)
        XCTAssertNotNil(spots[0].photoURL)
        XCTAssertTrue(spots[1].isApproximate)
        XCTAssertEqual(spots[1].approximateRadius, 80)
        XCTAssertTrue(spots[1].isAirside)
    }

    func testZones() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","id":"nea-nsz-1","geometry":{"type":"Polygon","coordinates":[[[103.83,1.30],[103.84,1.30],[103.84,1.31],[103.83,1.31],[103.83,1.30]]]},
           "properties":{"kind":"nsz","name":"Orchard Road No-Smoking Zone","source":"nea","buffer":0}},
          {"type":"Feature","id":7,"geometry":{"type":"MultiPolygon","coordinates":[
              [[[103.80,1.35],[103.81,1.35],[103.81,1.36],[103.80,1.35]]],
              [[[103.90,1.35],[103.91,1.35],[103.91,1.36],[103.90,1.35]]]]},
           "properties":{"kind":"park","name":null,"source":"nparks","buffer":0}},
          {"type":"Feature","id":"osm-node-1","geometry":{"type":"Point","coordinates":[103.85,1.29]},
           "properties":{"kind":"bus_stop","name":"Opp Raffles Place","source":"osm","buffer":11}},
          {"type":"Feature","id":"osm-node-2","geometry":{"type":"Point","coordinates":[103.85,1.29]},
           "properties":{"kind":"space_elevator","source":"osm","buffer":5}},
          {"type":"Feature","id":"line","geometry":{"type":"LineString","coordinates":[[103.8,1.3],[103.9,1.3]]},
           "properties":{"kind":"park","source":"osm"}}
        ]}
        """
        let zones = try GeoJSONDecoding.zones(from: Data(json.utf8))
        XCTAssertEqual(zones.map(\.id), ["nea-nsz-1", "7", "osm-node-1", "osm-node-2"], "the LineString is skipped")
        XCTAssertEqual(zones[0].kind, .nsz)
        XCTAssertTrue(zones[0].contains(Coordinate(latitude: 1.305, longitude: 103.835)))
        guard case .polygons(let parts) = zones[1].geometry else { return XCTFail("expected polygons") }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(zones[2].kind, .busStop)
        XCTAssertEqual(zones[2].buffer, 11)
        XCTAssertEqual(zones[3].kind, .other, "an unknown kind still counts as a no-smoking place")
    }

    func testRetailers() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","id":"hsa-238801-0","geometry":{"type":"Point","coordinates":[103.832,1.304]},
           "properties":{"name":"7-Eleven","licensee":"7-Eleven (Dairy Farm) Pte Ltd","address":"2 Orchard Turn, #B4-12, Singapore 238801",
                         "postal":"238801","category":"convenience","brand":"7-Eleven","building":"ION Orchard",
                         "validity":"01/09/2025 - 31/08/2026"}},
          {"type":"Feature","id":"hsa-1","geometry":{"type":"Point","coordinates":[103.9,1.35]},
           "properties":{"name":"Heng Lai Heng Trading","address":"20 Woodlands Link","postal":"738733","category":"mystery"}}
        ]}
        """
        let shops = try GeoJSONDecoding.retailers(from: Data(json.utf8))
        XCTAssertEqual(shops.count, 2)
        XCTAssertEqual(shops[0].category, .convenience)
        XCTAssertEqual(shops[0].brand, "7-Eleven")
        XCTAssertEqual(shops[1].category, .other)
        XCTAssertNil(shops[1].licensee)
    }

    func testMalformedFileThrows() {
        XCTAssertThrowsError(try GeoJSONDecoding.spots(from: Data("not json".utf8)))
    }
}
