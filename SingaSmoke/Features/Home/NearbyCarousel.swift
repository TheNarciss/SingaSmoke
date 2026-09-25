import SingaSmokeCore
import SwiftUI

/// The nearest places as swipeable cards along the bottom of the map, nearest first.
struct NearbyCarousel: View {
    let mode: AppMode
    let spots: [RankedPlace<SmokingSpot>]
    let shops: [RankedPlace<Retailer>]
    let referenceIsUser: Bool
    let onOpenSpot: (SmokingSpot) -> Void
    let onOpenShop: (Retailer) -> Void
    let onGo: (GuidanceTarget) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                switch mode {
                case .smoke:
                    if spots.isEmpty { placeholder }
                    ForEach(Array(spots.enumerated()), id: \.element.id) { index, place in
                        PlaceCard(
                            symbol: place.item.glyph,
                            tint: place.item.tint,
                            kicker: kicker(index: index, noun: "smoking spot"),
                            title: place.item.name,
                            subtitle: place.item.details.isEmpty ? place.item.source.label : place.item.details,
                            walking: place.walking,
                            caveat: place.item.caveat,
                            onOpen: { onOpenSpot(place.item) },
                            onGo: { onGo(GuidanceTarget(spot: place.item)) }
                        )
                    }
                case .buy:
                    if shops.isEmpty { placeholder }
                    ForEach(Array(shops.enumerated()), id: \.element.id) { index, place in
                        PlaceCard(
                            symbol: place.item.category.symbol,
                            tint: place.item.category.color,
                            kicker: kicker(index: index, noun: "shop"),
                            title: place.item.name,
                            subtitle: place.item.building ?? place.item.address,
                            walking: place.walking,
                            caveat: nil,
                            onOpen: { onOpenShop(place.item) },
                            onGo: { onGo(GuidanceTarget(retailer: place.item)) }
                        )
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 18)   // room for the card shadows
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.vertical, -18)
    }

    private func kicker(index: Int, noun: String) -> String {
        if index == 0 { return referenceIsUser ? "Nearest \(noun)" : "Nearest to the map centre" }
        return "\(index + 1)\(ordinalSuffix(index + 1)) nearest"
    }

    private func ordinalSuffix(_ n: Int) -> String {
        switch n % 10 {
        case 2 where n % 100 != 12: return "nd"
        case 3 where n % 100 != 13: return "rd"
        default: return "th"
        }
    }

    private var placeholder: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Looking around…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .containerRelativeFrame(.horizontal) { length, _ in length - 32 }
        .card()
    }
}

/// One card: what it is, how far on foot, and a Go button.
struct PlaceCard: View {
    let symbol: String
    let tint: Color
    let kicker: String
    let title: String
    let subtitle: String
    let walking: WalkingDistance
    let caveat: String?
    let onOpen: () -> Void
    let onGo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    IconCircle(symbol: symbol, tint: tint, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kicker.uppercased())
                            .font(.caption2.weight(.heavy))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the details")

            HStack(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        walkingChip
                        if let caveat { Chip(text: caveat, tint: Brand.warning).fixedSize() }
                    }
                    walkingChip
                }
                Spacer(minLength: 4)
                Button(action: onGo) {
                    Label("Go", systemImage: "arrow.turn.up.right")
                }
                .buttonStyle(.pill(.primary, compact: true))
                .fixedSize()
                .accessibilityLabel("Walk to \(title)")
            }
        }
        .padding(16)
        .containerRelativeFrame(.horizontal) { length, _ in length - 48 }
        .card(radius: 28)
    }

    private var walkingChip: some View {
        Chip(text: walking.chipText, symbol: "figure.walk", tint: .primary).fixedSize()
    }
}
