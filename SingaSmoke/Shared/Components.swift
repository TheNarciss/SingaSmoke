import SingaSmokeCore
import SwiftUI

/// "Official" / "Indicative", plus "Approximate" when the pin is not exact. Icons, not colour alone.
struct ReliabilityChips: View {
    let reliability: Reliability
    var approximate = false

    var body: some View {
        HStack(spacing: 6) {
            Chip(text: reliability.label, symbol: reliability.symbol, tint: reliability.color)
            if approximate {
                Chip(text: "Approximate", symbol: "scope", tint: Brand.warning)
            }
        }
    }
}

/// One line of a full list: icon, name, detail, walking time.
struct PlaceRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String?
    let walking: WalkingDistance
    var caveat: String?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconCircle(symbol: symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let caveat {
                    Text(caveat)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.warning)
                }
            }
            Spacer(minLength: 8)
            Text(walking.chipText)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, subtitle, caveat, Format.spokenWalking(walking)].compactMap { $0 }.joined(separator: ", "))
    }
}
