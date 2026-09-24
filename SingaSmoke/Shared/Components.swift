import SingaSmokeCore
import SwiftUI

/// "Officiel" / "Indicatif", with an icon so it never relies on colour alone.
struct ReliabilityBadge: View {
    let reliability: Reliability
    var approximate = false

    var body: some View {
        HStack(spacing: 6) {
            Label(reliability.label, systemImage: reliability.symbol)
                .foregroundStyle(reliability.color)
            if approximate {
                Label("Position approximative", systemImage: "scope")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
    }
}

/// One line of a "nearest" list: icon, name, detail, walking distance.
struct PlaceRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String?
    let walking: WalkingDistance
    var badge: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(Format.walking(walking))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.18), in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, subtitle, Format.spokenWalking(walking), badge].compactMap { $0 }.joined(separator: ", "))
    }
}

extension SmokingSpot {
    var rowBadge: String? {
        if isAirside { return "Zone transit" }
        if isApproximate { return "≈ position" }
        if reliability == .indicative { return "Indicatif" }
        return nil
    }

    var tint: Color { reliability == .official ? .green : .mint }
}

/// A round floating button over the map.
struct MapButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
                .shadow(radius: 2, y: 1)
        }
        .accessibilityLabel(label)
    }
}
