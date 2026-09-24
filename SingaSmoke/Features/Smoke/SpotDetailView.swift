import SingaSmokeCore
import SwiftUI

/// Everything known about one smoking spot, with the ways to get there.
struct SpotDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let spot: SmokingSpot
    var onGo: () -> Void

    @State private var walking: WalkingDistance?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(spot.name)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(spot.source.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ReliabilityBadge(reliability: spot.reliability, approximate: spot.isApproximate)
                }
                .padding(.vertical, 4)

                if !spot.details.isEmpty {
                    LabeledContent("Where") {
                        Text(spot.details)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let level = spot.level, !level.isEmpty {
                    LabeledContent("Level", value: level)
                }
                if let hours = spot.openingHours {
                    LabeledContent("Opening hours", value: hours)
                }
                LabeledContent("Distance") {
                    Text(Format.walking(walking ?? currentEstimate))
                        .monospacedDigit()
                }
            }

            if spot.isApproximate || spot.isAirside || spot.reliability == .indicative {
                Section {
                    if spot.isApproximate {
                        Label(approximateText, systemImage: "scope")
                    }
                    if spot.isAirside {
                        Label("Transit area: past immigration, with a boarding pass.", systemImage: "airplane.departure")
                    }
                    if spot.reliability == .indicative {
                        Label(Reliability.indicative.explanation, systemImage: Reliability.indicative.symbol)
                    }
                }
                .font(.subheadline)
            }

            if let photo = spot.photoURL {
                Section {
                    AsyncImage(url: photo) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .accessibilityLabel("NEA photo of the spot: \(spot.details)")
                        case .failure:
                            Label("Photo unavailable offline", systemImage: "wifi.slash")
                                .foregroundStyle(.secondary)
                        default:
                            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                } header: {
                    Text("Official NEA photo")
                } footer: {
                    Text("The yellow box painted on the ground marks the exact spot.")
                }
            }

            Section {
                Button(action: onGo) {
                    Label("Walking directions in the app", systemImage: "figure.walk")
                        .font(.headline)
                }
                Button {
                    ExternalMaps.openInAppleMaps(spot.coordinate, name: spot.name)
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                }
                Button {
                    openURL(ExternalMaps.googleMapsURL(spot.coordinate))
                } label: {
                    Label("Open in Google Maps", systemImage: "globe")
                }
            }

            Section {
                if let updated = Format.date(spot.updated) {
                    LabeledContent("Updated by the source", value: updated)
                }
                LabeledContent("Source", value: spot.source.publisher)
                if let url = spot.sourceURL {
                    Link("View the source", destination: url)
                }
            } footer: {
                Text(Legal.signage)
            }
        }
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task(id: spot.id) {
            guard model.referenceIsUser else { return }
            walking = await WalkingRouter.walkingETA(from: model.reference, to: spot.coordinate)
        }
    }

    private var approximateText: String {
        if let radius = spot.approximateRadius {
            return "The pin may be up to \(Format.distance(radius)) from the actual spot: follow the description on site."
        }
        return "The pin is approximate: follow the description on site."
    }

    private var currentEstimate: WalkingDistance {
        model.nearestSpots.first { $0.item.id == spot.id }?.walking
            ?? .estimate(straightLine: Geo.distance(model.reference, spot.coordinate))
    }
}
