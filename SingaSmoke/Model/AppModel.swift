import Foundation
import MapKit
import Observation
import SingaSmokeCore

/// App state: the bundled data, the user's position, the verdict and the nearest places.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case loading
        case ready
        case failed(String)
    }

    static let singaporeCentre = Coordinate(latitude: 1.3521, longitude: 103.8198)

    private(set) var phase: Phase = .loading
    private(set) var data: SingaSmokeData?

    let location = LocationService()
    @ObservationIgnored let router = WalkingRouter()

    /// Where distances are measured from: the user when in Singapore, the map centre otherwise.
    private(set) var reference: Coordinate = AppModel.singaporeCentre
    private(set) var referenceIsUser = false
    private(set) var verdict: Verdict = .noLocation
    private(set) var nearestSpots: [RankedPlace<SmokingSpot>] = []
    private(set) var nearestRetailers: [RankedPlace<Retailer>] = []

    var retailerCategories: Set<RetailCategory> = Set(RetailCategory.allCases) {
        didSet {
            refreshRetailers()
            refineWalking()
        }
    }

    @ObservationIgnored private var refineGeneration = 0

    // MARK: Loading

    func load() async {
        guard data == nil else { return }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { () throws -> SingaSmokeData in
                guard let directory = Bundle.main.url(forResource: "Data", withExtension: nil) else {
                    throw SingaSmokeData.LoadError.missing("Data")
                }
                return try SingaSmokeData.load(from: directory)
            }.value
            data = loaded
            phase = .ready
            locationChanged()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    // MARK: Updates

    /// Called whenever the GPS fix changes.
    func locationChanged() {
        guard let data else { return }
        let fix = location.fix
        verdict = data.verdict(for: fix)
        if let fix, Geo.singapore.contains(fix.coordinate) {
            reference = fix.coordinate
            referenceIsUser = true
        } else {
            referenceIsUser = false
        }
        refreshSpots()
        refreshRetailers()
        refineWalking()
    }

    /// Without a usable fix, distances follow the centre of the map.
    func mapCentreChanged(_ centre: Coordinate) {
        guard !referenceIsUser, Geo.singapore.contains(centre) else { return }
        guard Geo.distance(centre, reference) > 50 else { return }
        reference = centre
        refreshSpots()
        refreshRetailers()
    }

    var filteredRetailers: [Retailer] {
        guard let data else { return [] }
        if retailerCategories.count == RetailCategory.allCases.count { return data.retailers }
        return data.retailers.filter { retailerCategories.contains($0.category) }
    }

    /// The nearest place to smoke for the banner: never airside, which needs a boarding pass.
    var nearestLegalSpot: RankedPlace<SmokingSpot>? {
        nearestSpots.first { !$0.item.isAirside }
    }

    private func refreshSpots() {
        guard let data else { return }
        nearestSpots = Ranking.nearest(data.spots, to: reference, limit: 30)
    }

    private func refreshRetailers() {
        nearestRetailers = Ranking.nearest(filteredRetailers, to: reference, limit: 30)
    }

    /// Asks Apple for real walking distances of the closest places. The router answers from its
    /// cache until the user has moved, and spaces its network batches out.
    private func refineWalking() {
        guard referenceIsUser else { return }
        let origin = reference
        refineGeneration += 1
        let generation = refineGeneration
        let spots = nearestSpots
        let retailers = nearestRetailers
        Task { [weak self] in
            guard let self else { return }
            let refinedSpots = await router.refine(spots, from: origin)
            let refinedRetailers = await router.refine(retailers, from: origin, limit: 5)
            guard generation == refineGeneration else {
                // The user moved while Apple answered. The answers are cached: apply what fits
                // the current lists, without asking again.
                nearestSpots = router.cached(nearestSpots, from: reference)
                nearestRetailers = router.cached(nearestRetailers, from: reference)
                return
            }
            nearestSpots = refinedSpots
            nearestRetailers = refinedRetailers
        }
    }
}
