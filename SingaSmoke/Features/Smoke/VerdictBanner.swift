import SingaSmokeCore
import SwiftUI
import UIKit

/// The answer to "am I risking a fine here?", and the nearest place where the answer is no.
struct VerdictBanner: View {
    let verdict: Verdict
    let nearest: RankedPlace<SmokingSpot>?
    let locationDenied: Bool
    var onGo: (SmokingSpot) -> Void = { _ in }
    var onShowExit: () -> Void = {}

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: style.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(style.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if hasDetails {
                    Button {
                        withAnimation(.snappy) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up.circle" : "info.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel(expanded ? "Masquer les détails" : "Afficher les détails")
                }
            }

            if expanded {
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            actions
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style.tint.opacity(0.9), lineWidth: 2)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: Content per verdict

    private struct Style {
        let symbol: String
        let tint: Color
    }

    private var style: Style {
        switch verdict {
        case .noLocation: return Style(symbol: locationDenied ? "location.slash" : "location.magnifyingglass", tint: .gray)
        case .outsideSingapore: return Style(symbol: "globe.asia.australia", tint: .gray)
        case .atSpot: return Style(symbol: "checkmark.circle.fill", tint: .green)
        case .prohibited: return Style(symbol: "nosign", tint: .red)
        case .nearZone: return Style(symbol: "exclamationmark.triangle.fill", tint: .orange)
        case .clear: return Style(symbol: "checkmark.circle", tint: .teal)
        }
    }

    private var title: String {
        switch verdict {
        case .noLocation:
            return locationDenied ? "Localisation désactivée" : "Recherche de ta position…"
        case .outsideSingapore:
            return "Tu n'es pas à Singapour"
        case .atSpot(let spot, _, _):
            return spot.reliability == .official ? "Zone fumeur autorisée" : "Coin fumeur signalé ici"
        case .prohibited(let hit, _, _):
            return hit.isCertain ? "Tu es dans une zone interdite" : "Tu es sans doute en zone interdite"
        case .nearZone:
            return "Limite d'une zone interdite"
        case .clear:
            return "Zone OK : aucune interdiction connue ici"
        }
    }

    private var subtitle: String? {
        switch verdict {
        case .noLocation:
            return locationDenied ? "Active-la dans Réglages pour savoir si tu peux fumer ici." : nil
        case .outsideSingapore:
            return "Les distances partent du centre de la carte."
        case .atSpot(let spot, let distance, _):
            return "\(spot.name) · \(Format.distance(distance))"
        case .prohibited(let hit, _, _):
            return "\(hit.zone.title). Sors à \(Format.distance(hit.exitDistance)) \(hit.exitDirection.towards)."
        case .nearZone(let hit):
            return "\(hit.zone.title) à \(Format.distance(max(0, hit.signedDistance))) : ton GPS ne permet pas de trancher."
        case .clear:
            return "En plein air, hors abri, loin des entrées : en principe autorisé."
        }
    }

    private var details: [String] {
        var lines: [String] = []
        switch verdict {
        case .atSpot(let spot, _, let caution):
            if !spot.details.isEmpty { lines.append(spot.details) }
            if spot.reliability == .indicative { lines.append(Reliability.indicative.explanation) }
            if let caution { lines.append("Attention : \(caution.zone.title) à \(Format.distance(max(0, caution.signedDistance))).") }
        case .prohibited(let hit, let others, let spotHere):
            lines.append(hit.zone.kind.rule)
            for other in others.prefix(3) { lines.append("Aussi : \(other.zone.title).") }
            if spotHere != nil {
                lines.append("Un coin fumeur est signalé ici sur OpenStreetMap, mais la règle de la zone l'emporte.")
            }
            if hit.zone.reliability == .indicative { lines.append("Zone tirée d'OpenStreetMap : indicative.") }
            lines.append(Legal.fine)
        case .nearZone(let hit):
            lines.append(hit.zone.kind.rule)
        case .clear(let nearby):
            if let nearby { lines.append("À proximité : \(nearby.zone.title), à \(Format.distance(nearby.signedDistance)).") }
            lines.append(Legal.unmapped)
        default:
            break
        }
        lines.append(Legal.signage)
        return lines
    }

    private var hasDetails: Bool {
        switch verdict {
        case .noLocation, .outsideSingapore: return false
        default: return true
        }
    }

    @ViewBuilder
    private var actions: some View {
        if case .noLocation = verdict, locationDenied {
            Button("Ouvrir Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        } else {
            if case .prohibited = verdict {
                Button(action: onShowExit) {
                    Label("Voir la sortie de zone sur la carte", systemImage: "figure.walk")
                }
                .buttonStyle(.bordered)
            }
            nearestButton
        }
    }

    @ViewBuilder
    private var nearestButton: some View {
        if let nearest, !isAtNearest {
            Button {
                onGo(nearest.item)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Spot fumeur le plus proche")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(nearest.item.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(Format.walking(nearest.walking))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Label("Y aller", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spot fumeur le plus proche : \(nearest.item.name), \(Format.spokenWalking(nearest.walking))")
            .accessibilityHint("Affiche l'itinéraire à pied")
        }
    }

    private var isAtNearest: Bool {
        if case .atSpot(let spot, _, _) = verdict { return spot.id == nearest?.item.id }
        return false
    }
}
