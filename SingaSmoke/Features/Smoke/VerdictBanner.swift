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
                    .accessibilityLabel(expanded ? "Hide details" : "Show details")
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
            return locationDenied ? "Location is off" : "Finding your location…"
        case .outsideSingapore:
            return "You're not in Singapore"
        case .atSpot(let spot, _, _):
            return spot.reliability == .official ? "Designated smoking area" : "Smoking spot reported here"
        case .prohibited(let hit, _, _):
            return hit.isCertain ? "You're in a no-smoking zone" : "You're probably in a no-smoking zone"
        case .nearZone:
            return "Edge of a no-smoking zone"
        case .clear:
            return "Zone OK: no known restriction here"
        }
    }

    private var subtitle: String? {
        switch verdict {
        case .noLocation:
            return locationDenied ? "Turn it on in Settings to know whether you can smoke here." : nil
        case .outsideSingapore:
            return "Distances are measured from the centre of the map."
        case .atSpot(let spot, let distance, _):
            return "\(spot.name) · \(Format.distance(distance))"
        case .prohibited(let hit, _, _):
            return "\(hit.zone.title). Way out: \(Format.distance(hit.exitDistance)) \(hit.exitDirection.towards)."
        case .nearZone(let hit):
            return "\(hit.zone.title) \(Format.distance(max(0, hit.signedDistance))) away: your GPS can't tell for sure."
        case .clear:
            return "Outdoors, not under a shelter, away from entrances: generally allowed."
        }
    }

    private var details: [String] {
        var lines: [String] = []
        switch verdict {
        case .atSpot(let spot, _, let caution):
            if !spot.details.isEmpty { lines.append(spot.details) }
            if spot.reliability == .indicative { lines.append(Reliability.indicative.explanation) }
            if let caution { lines.append("Careful: \(caution.zone.title) \(Format.distance(max(0, caution.signedDistance))) away.") }
        case .prohibited(let hit, let others, let spotHere):
            lines.append(hit.zone.kind.rule)
            for other in others.prefix(3) { lines.append("Also: \(other.zone.title).") }
            if spotHere != nil {
                lines.append("OpenStreetMap reports a smoking spot here, but the zone's rule wins.")
            }
            if hit.zone.reliability == .indicative { lines.append("Zone taken from OpenStreetMap: indicative.") }
            lines.append(Legal.fine)
        case .nearZone(let hit):
            lines.append(hit.zone.kind.rule)
        case .clear(let nearby):
            if let nearby { lines.append("Nearby: \(nearby.zone.title), \(Format.distance(nearby.signedDistance)) away.") }
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
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        } else {
            if case .prohibited = verdict {
                Button(action: onShowExit) {
                    Label("Show the way out on the map", systemImage: "figure.walk")
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
                        Text("Nearest smoking spot")
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
                    Label("Go", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Nearest smoking spot: \(nearest.item.name), \(Format.spokenWalking(nearest.walking))")
            .accessibilityHint("Shows the walking route")
        }
    }

    private var isAtNearest: Bool {
        if case .atSpot(let spot, _, _) = verdict { return spot.id == nearest?.item.id }
        return false
    }
}
