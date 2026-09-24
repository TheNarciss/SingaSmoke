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

            VStack(spacing: 12) {
                instructionCard
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    FloatingButton(symbol: "location.north.line.fill", label: "Centre on my location") { recenter += 1 }
                }
                bottomCard
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
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

    /// The next manoeuvre, big and high-contrast: readable at arm's length, in the sun.
    private var instructionCard: some View {
        HStack(alignment: .center, spacing: 14) {
            instructionIcon
            VStack(alignment: .leading, spacing: 3) {
                instructionText
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(arrived ? Brand.allowed : Color(white: 0.09), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .animation(.snappy, value: arrived)
    }

    @ViewBuilder
    private var instructionIcon: some View {
        let symbol: String = {
            if arrived { return "flag.checkered" }
            if user == nil { return "location.magnifyingglass" }
            if let progress { return Self.maneuverSymbol(progress.nextInstruction) }
            if computing { return "hourglass" }
            return "wifi.slash"
        }()
        Image(systemName: symbol)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(arrived ? Brand.allowed : .white)
            .frame(width: 58, height: 58)
            .background(arrived ? Color.white : Brand.allowed, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var instructionText: some View {
        if arrived {
            Text("You have arrived")
                .font(.title2.weight(.heavy))
            Text(target.detail ?? target.name)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Text(Legal.signage)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        } else if user == nil {
            Text("Waiting for your location…")
                .font(.headline)
        } else if let progress {
            Text(Format.distance(progress.distanceToNext))
                .font(.largeTitle.weight(.heavy))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(progress.nextInstruction ?? "Continue to the destination")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        } else if computing {
            Text("Finding the route…")
                .font(.headline)
        } else if let straightLine, let user {
            Text("No route. No network?")
                .font(.headline)
            Text("\(Format.distance(straightLine)) as the crow flies, \(CompassDirection(bearing: Geo.bearing(from: user, to: target.coordinate)).towards).")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { Task { await computeRoute(force: true) } }
                .buttonStyle(.pill(.secondary, compact: true))
                .padding(.top, 6)
        }
    }

    /// Where the user is heading, how long it takes, and the way out of guidance.
    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let remaining {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Format.duration(remaining / WalkingDistance.walkingSpeed))
                                .font(.title2.weight(.heavy))
                                .foregroundStyle(Brand.allowed)
                            Text(Format.distance(remaining))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                    }
                    Text(target.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let detail = target.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button("End") { dismiss() }
                    .buttonStyle(.pill(.danger, compact: true))
                    .accessibilityLabel("End the walk")
            }
            HStack(spacing: 10) {
                Button {
                    ExternalMaps.openInAppleMaps(target.coordinate, name: target.name)
                } label: {
                    Label("Apple Maps", systemImage: "map.fill")
                }
                .buttonStyle(.pill(.secondary, compact: true))
                Button {
                    openURL(ExternalMaps.googleMapsURL(target.coordinate))
                } label: {
                    Label("Google Maps", systemImage: "globe")
                }
                .buttonStyle(.pill(.secondary, compact: true))
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .card(radius: 28)
    }

    /// Metres left: along the route when there is one, else a walking estimate from the straight line.
    private var remaining: Double? {
        if let progress { return progress.remaining }
        return straightLine.map { WalkingDistance.estimate(straightLine: $0).meters }
    }

    /// An arrow for an English MapKit instruction ("Turn left onto…", "Keep right…"), by whole words.
    static func maneuverSymbol(_ instruction: String?) -> String {
        guard let instruction else { return "flag.checkered" }
        let words = Set(instruction.lowercased().split { !$0.isLetter }.map(String.init))
        let gentle = !words.isDisjoint(with: ["slight", "slightly", "keep", "bear"])
        if words.contains("left") { return gentle ? "arrow.up.left" : "arrow.turn.up.left" }
        if words.contains("right") { return gentle ? "arrow.up.right" : "arrow.turn.up.right" }
        if words.contains("arrive") || words.contains("destination") { return "flag.checkered" }
        if words.contains("stairs") || words.contains("steps") { return "figure.stairs" }
        return "arrow.up"
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
