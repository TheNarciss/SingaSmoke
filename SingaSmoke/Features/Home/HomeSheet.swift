import SingaSmokeCore
import SwiftUI

/// A place picked on the map or in the list, shown in the bottom sheet.
enum SelectedPlace: Hashable {
    case spot(SmokingSpot)
    case shop(Retailer)
}

/// The bottom sheet, as in a maps app: folded, the nearest place and its Go button; pulled up,
/// everything nearby; a place's details when one is picked.
struct HomeSheet: View {
    let mode: AppMode
    let selection: SelectedPlace?
    let onSelect: (SelectedPlace) -> Void
    let onClose: () -> Void
    let onGo: (GuidanceTarget) -> Void

    var body: some View {
        switch selection {
        case .spot(let spot)?:
            SpotDetailView(spot: spot, onGo: { onGo(GuidanceTarget(spot: spot)) }, onClose: onClose)
                .id(spot.id)
        case .shop(let shop)?:
            RetailerDetailView(retailer: shop, onGo: { onGo(GuidanceTarget(retailer: shop)) }, onClose: onClose)
                .id(shop.id)
        case nil:
            NearbyList(mode: mode, onSelect: onSelect, onGo: onGo)
        }
    }
}

/// The nearest place first, big enough to read in the folded sheet, then the rest of the list.
struct NearbyList: View {
    @Environment(AppModel.self) private var model
    let mode: AppMode
    let onSelect: (SelectedPlace) -> Void
    let onGo: (GuidanceTarget) -> Void

    @State private var officialOnly = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch mode {
                case .smoke: smokeContent
                case .buy: buyContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)   // under the sheet's grabber
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Smoking spots

    @ViewBuilder
    private var smokeContent: some View {
        let places = officialOnly ? model.nearestSpots.filter { $0.item.reliability == .official } : model.nearestSpots
        if let first = places.first {
            Kicker(text: model.referenceIsUser ? "Nearest smoking spot" : "Nearest to the map centre")
            spotRow(first, prominent: true)
        } else {
            LookingAround()
        }

        HStack {
            Text("More nearby")
                .font(.headline)
            Spacer()
            Button {
                withAnimation(.snappy) { officialOnly.toggle() }
            } label: {
                Label("Official only", systemImage: officialOnly ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.footnote.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(officialOnly ? Color.white : .primary)
                    .background(officialOnly ? Brand.allowed : Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(officialOnly ? .isSelected : [])
        }
        .padding(.top, 22)
        .padding(.bottom, 4)

        ForEach(places.dropFirst()) { place in
            Divider()
            spotRow(place, prominent: false)
        }

        Footnote(text: model.referenceIsUser
                 ? "Walking times come from Apple Maps when online; \"≈\" marks an estimate. \(Legal.signage)"
                 : "Without your location, distances are measured from the centre of the map.")
    }

    private func spotRow(_ place: RankedPlace<SmokingSpot>, prominent: Bool) -> some View {
        NearbyRow(symbol: place.item.glyph, tint: place.item.tint, title: place.item.name,
                  walking: place.walking, caveat: place.item.caveat, prominent: prominent,
                  onOpen: { onSelect(.spot(place.item)) },
                  onGo: { onGo(GuidanceTarget(spot: place.item)) })
    }

    // MARK: Shops

    @ViewBuilder
    private var buyContent: some View {
        if let first = model.nearestRetailers.first {
            Kicker(text: model.referenceIsUser ? "Nearest shop" : "Nearest to the map centre")
            shopRow(first, prominent: true)
        } else {
            LookingAround()
        }

        Text("Kinds of shop")
            .font(.headline)
            .padding(.top, 22)
        CategoryChips()
            .padding(.vertical, 4)

        Text("More nearby")
            .font(.headline)
            .padding(.top, 14)
            .padding(.bottom, 4)

        ForEach(model.nearestRetailers.dropFirst()) { place in
            Divider()
            shopRow(place, prominent: false)
        }

        Footnote(text: "HSA register of licensed tobacco retailers, located to the building of their postal code. No opening hours. \(Legal.vape)")
    }

    private func shopRow(_ place: RankedPlace<Retailer>, prominent: Bool) -> some View {
        NearbyRow(symbol: place.item.category.symbol, tint: place.item.category.color, title: place.item.name,
                  walking: place.walking, caveat: nil, prominent: prominent,
                  onOpen: { onSelect(.shop(place.item)) },
                  onGo: { onGo(GuidanceTarget(retailer: place.item)) })
    }
}

/// One place: icon, name, walking time, and a Go button. Tap the row for the details.
struct NearbyRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let walking: WalkingDistance
    let caveat: String?
    var prominent = false
    let onOpen: () -> Void
    let onGo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    IconCircle(symbol: symbol, tint: tint, size: prominent ? 44 : 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(prominent ? .headline : .subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: "figure.walk")
                            Text(walking.chipText)
                            if let caveat {
                                Text("· \(caveat)").foregroundStyle(Brand.warning)
                            }
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, Format.spokenWalking(walking), caveat].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint("Shows the details")

            Button(action: onGo) {
                Label("Go", systemImage: "arrow.turn.up.right")
            }
            .buttonStyle(.pill(.primary, compact: true))
            .fixedSize()
            .accessibilityLabel("Walk to \(title)")
        }
        .padding(.vertical, prominent ? 4 : 10)
    }
}

private struct Kicker: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.heavy))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
    }
}

private struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
    }
}

private struct LookingAround: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Looking around…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 52)
    }
}
