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
                    LabeledContent("Emplacement") {
                        Text(spot.details)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let level = spot.level, !level.isEmpty {
                    LabeledContent("Niveau", value: level)
                }
                if let hours = spot.openingHours {
                    LabeledContent("Horaires", value: hours)
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
                        Label("Zone transit : après l'immigration, avec une carte d'embarquement.", systemImage: "airplane.departure")
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
                                .accessibilityLabel("Photo NEA de l'emplacement : \(spot.details)")
                        case .failure:
                            Label("Photo indisponible hors ligne", systemImage: "wifi.slash")
                                .foregroundStyle(.secondary)
                        default:
                            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                } header: {
                    Text("Photo officielle NEA")
                } footer: {
                    Text("Le carré jaune au sol marque l'endroit exact.")
                }
            }

            Section {
                Button(action: onGo) {
                    Label("Itinéraire à pied dans l'app", systemImage: "figure.walk")
                        .font(.headline)
                }
                Button {
                    ExternalMaps.openInAppleMaps(spot.coordinate, name: spot.name)
                } label: {
                    Label("Ouvrir dans Plans", systemImage: "map")
                }
                Button {
                    openURL(ExternalMaps.googleMapsURL(spot.coordinate))
                } label: {
                    Label("Ouvrir dans Google Maps", systemImage: "globe")
                }
            }

            Section {
                if let updated = Format.date(spot.updated) {
                    LabeledContent("Mis à jour par la source", value: updated)
                }
                LabeledContent("Source", value: spot.source.publisher)
                if let url = spot.sourceURL {
                    Link("Voir la source", destination: url)
                }
            } footer: {
                Text(Legal.signage)
            }
        }
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { dismiss() }
            }
        }
        .task(id: spot.id) {
            guard model.referenceIsUser else { return }
            walking = await WalkingRouter.walkingETA(from: model.reference, to: spot.coordinate)
        }
    }

    private var approximateText: String {
        if let radius = spot.approximateRadius {
            return "Le repère peut être à \(Format.distance(radius)) du vrai emplacement : suis la description sur place."
        }
        return "Le repère est approximatif : suis la description sur place."
    }

    private var currentEstimate: WalkingDistance {
        model.nearestSpots.first { $0.item.id == spot.id }?.walking
            ?? .estimate(straightLine: Geo.distance(model.reference, spot.coordinate))
    }
}
