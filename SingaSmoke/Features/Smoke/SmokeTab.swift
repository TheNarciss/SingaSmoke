import MapKit
import SingaSmokeCore
import SwiftUI

/// Where the user is, whether they can smoke there, and the closest places where they can.
struct SmokeTab: View {
    @Environment(AppModel.self) private var model
    @State private var selectedSpot: SmokingSpot?
    @State private var guidance: GuidanceTarget?
    /// Guidance asked from a sheet: shown once the sheet is gone (two modals cannot overlap).
    @State private var pendingGuidance: GuidanceTarget?
    @State private var recenter = 0
    @State private var showExit = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                SingaMapView(
                    spots: model.data?.spots ?? [],
                    zoneIndex: model.data?.zoneIndex,
                    marker: exitMarker,
                    recenterToken: recenter,
                    onSelectSpot: { selectedSpot = $0 },
                    onRegionChange: { model.mapCentreChanged(Coordinate($0.center)) }
                )
                .ignoresSafeArea(edges: .top)
                .accessibilityLabel("Map of smoking and no-smoking areas")

                VStack(spacing: 10) {
                    VerdictBanner(
                        verdict: model.verdict,
                        nearest: model.nearestLegalSpot,
                        locationDenied: model.location.isDenied,
                        onGo: { guidance = GuidanceTarget(spot: $0) },
                        onShowExit: { showExit = true; recenter += 1 }
                    )
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        MapButton(symbol: "location.fill", label: "Centre on my location") { recenter += 1 }
                    }
                    NearestSpotsCard(places: Array(model.nearestSpots.prefix(3)),
                                     referenceIsUser: model.referenceIsUser,
                                     onSelect: { selectedSpot = $0 },
                                     onShowAll: { path.append(SpotListRoute()) })
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SpotListRoute.self) { _ in
                SpotListView(onGo: { guidance = GuidanceTarget(spot: $0) })
            }
        }
        .sheet(item: $selectedSpot, onDismiss: startPendingGuidance) { spot in
            NavigationStack {
                SpotDetailView(spot: spot, onGo: {
                    pendingGuidance = GuidanceTarget(spot: spot)
                    selectedSpot = nil
                })
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(model)
        }
        .fullScreenCover(item: $guidance) { target in
            GuidanceView(target: target)
                .environment(model)
        }
        .onChange(of: model.verdictIsProhibited) { _, prohibited in
            if !prohibited { showExit = false }
        }
    }

    private func startPendingGuidance() {
        guard let pending = pendingGuidance else { return }
        pendingGuidance = nil
        guidance = pending
    }

    private var exitMarker: MarkerAnnotation? {
        guard showExit, case .prohibited(let hit, _, _) = model.verdict else { return nil }
        return MarkerAnnotation(.exit, coordinate: hit.exit, title: "Way out of the zone")
    }
}

struct SpotListRoute: Hashable {}

extension AppModel {
    var verdictIsProhibited: Bool {
        if case .prohibited = verdict { return true }
        return false
    }
}

/// The three closest spots, over the bottom of the map.
struct NearestSpotsCard: View {
    let places: [RankedPlace<SmokingSpot>]
    let referenceIsUser: Bool
    let onSelect: (SmokingSpot) -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(referenceIsUser ? "Nearest on foot" : "Nearest to the map centre")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("See all", action: onShowAll)
                    .font(.subheadline)
            }
            if places.isEmpty {
                Text("Loading…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(places) { place in
                Button {
                    onSelect(place.item)
                } label: {
                    PlaceRow(symbol: place.item.glyph, tint: place.item.tint, title: place.item.name,
                             subtitle: place.item.details, walking: place.walking, badge: place.item.rowBadge)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the details")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Every spot, nearest first by walking distance.
struct SpotListView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: SmokingSpot?
    @State private var pending: SmokingSpot?
    @State private var officialOnly = false
    var onGo: (SmokingSpot) -> Void

    var body: some View {
        List {
            Section {
                Toggle("Official sources only", isOn: $officialOnly)
            } footer: {
                Text(model.referenceIsUser
                     ? "Walking distances come from Apple Maps when online; \"≈\" marks an estimate."
                     : "Without your location, distances are measured from the centre of the map.")
            }
            Section("Smoking spots") {
                ForEach(places) { place in
                    Button {
                        selected = place.item
                    } label: {
                        PlaceRow(symbol: place.item.glyph, tint: place.item.tint, title: place.item.name,
                                 subtitle: place.item.details, walking: place.walking, badge: place.item.rowBadge)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Smoking spots")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected, onDismiss: {
            if let spot = pending { pending = nil; onGo(spot) }
        }) { spot in
            NavigationStack {
                SpotDetailView(spot: spot, onGo: {
                    pending = spot
                    selected = nil
                })
            }
            .presentationDetents([.medium, .large])
            .environment(model)
        }
    }

    private var places: [RankedPlace<SmokingSpot>] {
        officialOnly ? model.nearestSpots.filter { $0.item.reliability == .official } : model.nearestSpots
    }
}
