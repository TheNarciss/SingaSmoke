import MapKit
import SingaSmokeCore
import UIKit

/// Real walking distances from Apple's router (network required, no API key).
/// Only the few closest places are asked for, answers are cached, and batches are spaced out:
/// MapKit throttles apps that send too many direction requests.
@MainActor
final class WalkingRouter {
    private struct Entry {
        let origin: Coordinate
        let walking: WalkingDistance
    }

    private var cache: [String: Entry] = [:]
    private var lastBatch = Date.distantPast

    /// How far the user may move before a cached walking distance is asked again.
    static let reuseRadius: Double = 40
    static let minimumInterval: TimeInterval = 12

    /// Replaces the estimate of the first `limit` places with Apple's walking distance where
    /// available, then sorts by it. Places that could not be routed keep their estimate.
    func refine<Item: Located>(_ places: [RankedPlace<Item>], from origin: Coordinate, limit: Int = 8) async -> [RankedPlace<Item>] {
        var result = places
        var missing: [(index: Int, id: String, destination: Coordinate)] = []
        for (i, place) in places.prefix(limit).enumerated() {
            if let hit = cache[place.id], Geo.distance(hit.origin, origin) < Self.reuseRadius {
                result[i].walking = hit.walking
            } else {
                missing.append((i, place.id, place.item.coordinate))
            }
        }
        if !missing.isEmpty, Date().timeIntervalSince(lastBatch) >= Self.minimumInterval {
            lastBatch = Date()
            let answers = await withTaskGroup(of: (Int, String, WalkingDistance?).self) { group in
                for entry in missing {
                    group.addTask {
                        let walking = await WalkingRouter.walkingETA(from: origin, to: entry.destination)
                        return (entry.index, entry.id, walking)
                    }
                }
                var collected: [(Int, String, WalkingDistance?)] = []
                for await answer in group { collected.append(answer) }
                return collected
            }
            for (index, id, walking) in answers {
                guard let walking else { continue }
                result[index].walking = walking
                cache[id] = Entry(origin: origin, walking: walking)
            }
        }
        return Ranking.byWalking(result)
    }

    /// Cache only, no network: walking distances already known from about here.
    func cached<Item: Located>(_ places: [RankedPlace<Item>], from origin: Coordinate) -> [RankedPlace<Item>] {
        var result = places
        for i in result.indices {
            if let hit = cache[result[i].id], Geo.distance(hit.origin, origin) < Self.reuseRadius {
                result[i].walking = hit.walking
            }
        }
        return Ranking.byWalking(result)
    }

    nonisolated static func walkingETA(from origin: Coordinate, to destination: Coordinate) async -> WalkingDistance? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.cl))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.cl))
        request.transportType = .walking
        do {
            let eta = try await MKDirections(request: request).calculateETA()
            return WalkingDistance(meters: eta.distance, seconds: eta.expectedTravelTime, isEstimate: false)
        } catch {
            return nil
        }
    }

    /// A full walking route, for the in-app guidance.
    nonisolated static func walkingRoute(from origin: Coordinate, to destination: Coordinate) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.cl))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.cl))
        request.transportType = .walking
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw MKError(.directionsNotFound) }
        return route
    }
}

/// Hand-off to the maps apps for turn-by-turn guidance.
enum ExternalMaps {
    @MainActor
    static func openInAppleMaps(_ destination: Coordinate, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: destination.cl))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    /// The universal link opens the Google Maps app when it is installed, the website otherwise.
    static func googleMapsURL(_ destination: Coordinate) -> URL {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "travelmode", value: "walking"),
        ]
        return components.url!
    }
}
