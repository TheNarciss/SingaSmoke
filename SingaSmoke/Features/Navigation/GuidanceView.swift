import MapKit
import SingaSmokeCore
import SwiftUI
import UIKit

/// Where the guidance leads.
struct GuidanceTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String?
    let coordinate: Coordinate

    init(spot: SmokingSpot) {
        id = "spot-\(spot.id)"
        name = spot.name
        detail = spot.details.isEmpty ? nil : spot.details
        coordinate = spot.coordinate
    }

    init(retailer: Retailer) {
        id = "shop-\(retailer.id)"
        name = retailer.name
        detail = retailer.address
        coordinate = retailer.coordinate
    }
}

/// Walking guidance inside the app: Apple's route drawn on the map, the next manoeuvre, and a
/// new route when the user strays. Needs the network for the route; without it, a compass bearing.
struct GuidanceView: View {
    let target: GuidanceTarget
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var route: MKRoute?
    @State private var computing = false
    @State private var failed = false
    @State private var lastRequest = Date.distantPast
    @State private var recenter = 0

    var body: some View {
        ZStack(alignment: .top) {
            SingaMapView(
                zoneIndex: model.data?.zoneIndex,
                marker: MarkerAnnotation(.destination, coordinate: target.coordinate, title: target.name),
                route: route?.polyline,
                followsHeading: true,
                recenterToken: recenter
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                instructionCard
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    MapButton(symbol: "location.north.line.fill", label: "Centre on my location") { recenter += 1 }
                }
                bottomBar
            }
            .padding(12)
        }
        .task { await computeRoute(force: true) }
        .onChange(of: model.location.fix) { _, _ in
            Task { await followUser() }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: State

    private var user: Coordinate? { model.location.fix?.coordinate }

    private var progress: RouteProgress? {
        guard let route, let user else { return nil }
        return RouteProgress(route: route, user: user.cl)
    }

    private var straightLine: Double? { user.map { Geo.distance($0, target.coordinate) } }

    private var arrived: Bool { (straightLine ?? .infinity) < 20 }

    // MARK: Views

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if arrived {
                Label("You have arrived", systemImage: "flag.checkered")
                    .font(.title2.weight(.bold))
                Text(target.detail ?? target.name)
                    .font(.body)
                Text(Legal.signage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if user == nil {
                Label("Waiting for your location…", systemImage: "location.magnifyingglass")
                    .font(.headline)
            } else if let progress {
                Text(progress.nextInstruction ?? "Continue to the destination")
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("in \(Format.distance(progress.distanceToNext))")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("\(Format.distance(progress.remaining)) · \(Format.duration(progress.remaining / WalkingDistance.walkingSpeed)) to go")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if computing {
                Label("Calculating the route…", systemImage: "hourglass")
                    .font(.headline)
            } else if let straightLine, let user {
                Label("No route available. No network?", systemImage: "wifi.slash")
                    .font(.headline)
                Text("The destination is \(Format.distance(straightLine)) away as the crow flies, \(CompassDirection(bearing: Geo.bearing(from: user, to: target.coordinate)).towards).")
                    .font(.subheadline)
                Button("Try again") { Task { await computeRoute(force: true) } }
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .font(.headline)
                if let detail = target.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            HStack(spacing: 8) {
                Button {
                    ExternalMaps.openInAppleMaps(target.coordinate, name: target.name)
                } label: {
                    Label("Apple Maps", systemImage: "map")
                }
                .buttonStyle(.bordered)
                Button {
                    openURL(ExternalMaps.googleMapsURL(target.coordinate))
                } label: {
                    Label("Google Maps", systemImage: "globe")
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button("End") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Routing

    private func computeRoute(force: Bool) async {
        guard let origin = user else { return }
        guard force || Date().timeIntervalSince(lastRequest) > 15 else { return }
        lastRequest = Date()
        computing = true
        defer { computing = false }
        do {
            route = try await WalkingRouter.walkingRoute(from: origin, to: target.coordinate)
            failed = false
        } catch {
            failed = true
        }
    }

    private func followUser() async {
        guard !arrived else { return }
        if route == nil {
            await computeRoute(force: false)
        } else if let progress, progress.distanceFromRoute > 40 {
            await computeRoute(force: false)   // strayed off the route
        }
    }
}

/// Where the user stands along a route: how far off it, what comes next, how much is left.
struct RouteProgress {
    let distanceFromRoute: Double
    let remaining: Double
    let distanceToNext: Double
    let nextInstruction: String?

    init?(route: MKRoute, user: CLLocationCoordinate2D) {
        let here = MKMapPoint(user)
        let steps = route.steps
        var best: (step: Int, offRoute: Double, restOfStep: Double)?
        for (i, step) in steps.enumerated() {
            let points = step.polyline.mapPoints
            guard points.count >= 2 else { continue }
            for j in 0..<(points.count - 1) {
                let foot = RouteProgress.closest(here, points[j], points[j + 1])
                let off = here.distance(to: foot)
                guard off < (best?.offRoute ?? .infinity) else { continue }
                var rest = foot.distance(to: points[j + 1])
                for k in (j + 1)..<(points.count - 1) { rest += points[k].distance(to: points[k + 1]) }
                best = (i, off, rest)
            }
        }
        guard let best else { return nil }
        let later = steps.dropFirst(best.step + 1)
        distanceFromRoute = best.offRoute
        distanceToNext = best.restOfStep
        remaining = best.restOfStep + later.reduce(0) { $0 + $1.distance }
        nextInstruction = later.first { !$0.instructions.isEmpty }?.instructions
    }

    static func closest(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> MKMapPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length2 = dx * dx + dy * dy
        guard length2 > 0 else { return a }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2))
        return MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
    }
}

extension MKMultiPoint {
    var mapPoints: [MKMapPoint] {
        Array(UnsafeBufferPointer(start: points(), count: pointCount))
    }
}
