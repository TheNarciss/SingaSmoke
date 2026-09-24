import SingaSmokeCore
import SwiftUI
import UIKit

/// "Can I smoke here?" in one glance: a coloured disc, a short verdict, a line of context.
/// Tap to unfold the rule, the other zones around and the fine.
struct StatusCard: View {
    let verdict: Verdict
    let locationDenied: Bool
    var onShowExit: () -> Void = {}

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                guard hasDetails else { return }
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    IconCircle(symbol: style.symbol, tint: style.tint, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(expanded ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    if hasDetails {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(hasDetails ? (expanded ? "Hides the details" : "Shows the details") : "")

            if case .prohibited(let hit, _, _) = verdict {
                Button(action: onShowExit) {
                    Label("Way out · \(Format.distance(hit.exitDistance)) \(hit.exitDirection.rawValue)", systemImage: "figure.walk")
                }
                .buttonStyle(.pill(.danger, compact: true))
            }

            if case .noLocation = verdict, locationDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.pill(.primary, compact: true))
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(details, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(.tertiary).frame(width: 5, height: 5).offset(y: -2)
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 26)
    }

    // MARK: Content per verdict

    private var style: (symbol: String, tint: Color) {
        switch verdict {
        case .noLocation: return (locationDenied ? "location.slash.fill" : "location.fill", .gray)
        case .outsideSingapore: return ("globe.asia.australia.fill", .gray)
        case .atSpot: return ("checkmark", Brand.allowed)
        case .prohibited: return ("nosign", Brand.danger)
        case .nearZone: return ("exclamationmark", Brand.warning)
        case .clear: return ("hand.thumbsup.fill", Brand.allowed)
        }
    }

    private var title: String {
        switch verdict {
        case .noLocation:
            return locationDenied ? "Location is off" : "Finding you…"
        case .outsideSingapore:
            return "Outside Singapore"
        case .atSpot(let spot, _, _):
            return spot.reliability == .official ? "Smoking area" : "Reported smoking spot"
        case .prohibited(let hit, _, _):
            return hit.isCertain ? "No smoking here" : "Probably no smoking here"
        case .nearZone:
            return "Near a no-smoking zone"
        case .clear:
            return "No known restriction"
        }
    }

    private var subtitle: String? {
        switch verdict {
        case .noLocation:
            return locationDenied ? "Turn it on to know whether you can smoke here." : nil
        case .outsideSingapore:
            return "Distances are measured from the centre of the map."
        case .atSpot(let spot, let distance, _):
            return "\(spot.name) · \(Format.distance(distance)) away"
        case .prohibited(let hit, _, _):
            return hit.zone.title
        case .nearZone(let hit):
            return "\(hit.zone.title), \(Format.distance(max(0, hit.signedDistance))) away. Your GPS can't tell for sure."
        case .clear:
            return "Outdoors, away from shelters and entrances: generally fine."
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
            if spotHere != nil { lines.append("OpenStreetMap reports a smoking spot here, but the zone's rule wins.") }
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
}
