import SingaSmokeCore
import SwiftUI

/// Everything known about one smoking spot, with the ways to get there.
struct SpotDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let spot: SmokingSpot
    var onGo: () -> Void

    @State private var walking: WalkingDistance?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !spot.details.isEmpty {
                    InfoBlock(symbol: "mappin.and.ellipse", title: "Where exactly", text: spot.details)
                }

                if let photo = spot.photoURL {
                    VStack(alignment: .leading, spacing: 8) {
                        AsyncImage(url: photo) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                                    .accessibilityLabel("NEA photo of the spot: \(spot.details)")
                            case .failure:
                                Label("Photo unavailable offline", systemImage: "wifi.slash")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            default:
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 230)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Text("Official NEA photo. The yellow box painted on the ground marks the exact spot.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if spot.isApproximate || spot.isAirside || spot.reliability == .indicative {
                    VStack(alignment: .leading, spacing: 10) {
                        if spot.isApproximate {
                            InfoBlock(symbol: "scope", title: "Approximate position", text: approximateText, tint: Brand.warning)
                        }
                        if spot.isAirside {
                            InfoBlock(symbol: "airplane.departure", title: "Transit area",
                                      text: "Past immigration, with a boarding pass.", tint: Brand.warning)
                        }
                        if spot.reliability == .indicative {
                            InfoBlock(symbol: Reliability.indicative.symbol, title: "Indicative",
                                      text: Reliability.indicative.explanation, tint: Brand.warning)
                        }
                    }
                }

                VStack(spacing: 10) {
                    Button(action: onGo) {
                        Label("Start walking", systemImage: "figure.walk")
                    }
                    .buttonStyle(.pill)
                    HStack(spacing: 10) {
                        Button {
                            ExternalMaps.openInAppleMaps(spot.coordinate, name: spot.name)
                        } label: {
                            Label("Apple Maps", systemImage: "map.fill")
                        }
                        .buttonStyle(.pill(.secondary))
                        Button {
                            openURL(ExternalMaps.googleMapsURL(spot.coordinate))
                        } label: {
                            Label("Google Maps", systemImage: "globe")
                        }
                        .buttonStyle(.pill(.secondary))
                    }
                }

                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .task(id: spot.id) {
            guard model.referenceIsUser else { return }
            walking = await WalkingRouter.walkingETA(from: model.reference, to: spot.coordinate)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            IconCircle(symbol: spot.glyph, tint: spot.tint, size: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(spot.name)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(spot.source.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { chips }
                    VStack(alignment: .leading, spacing: 6) { chips }
                }
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        Chip(text: (walking ?? currentEstimate).chipText, symbol: "figure.walk", tint: .primary)
        Chip(text: spot.reliability.label, symbol: spot.reliability.symbol, tint: spot.reliability.color)
        if let level = spot.level, !level.isEmpty {
            Chip(text: "Level \(level)", symbol: "stairs", tint: .secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Source: \(spot.source.publisher)")
                if let updated = Format.date(spot.updated) { Text("· updated \(updated)") }
            }
            if let hours = spot.openingHours { Text("Opening hours: \(hours)") }
            if let url = spot.sourceURL { Link("View the source", destination: url) }
            Text(Legal.signage)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
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

/// A small titled block of text with an icon, used in the detail sheets.
struct InfoBlock: View {
    let symbol: String
    let title: String
    let text: String
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.tertiarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
