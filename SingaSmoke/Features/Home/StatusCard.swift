import SingaSmokeCore
import SwiftUI
import UIKit

/// What the app says about where the user stands: an icon, a colour, a title, a line of context.
/// Shared by the status card and its minimised pill.
struct VerdictSummary {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String?

    init(_ verdict: Verdict, locationDenied: Bool) {
        switch verdict {
        case .noLocation:
            symbol = locationDenied ? "location.slash.fill" : "location.fill"
            tint = .gray
            title = locationDenied ? "Location is off" : "Finding you…"
            subtitle = locationDenied ? "Turn it on to know whether you can smoke here." : nil
        case .outsideSingapore:
            symbol = "globe.asia.australia.fill"
            tint = .gray
            title = "Outside Singapore"
            subtitle = "Distances are measured from the centre of the map."
        case .atSpot(let spot, let distance, _):
            symbol = "checkmark"
            tint = Brand.allowed
            title = spot.reliability == .official ? "Smoking area" : "Reported smoking spot"
            subtitle = "\(spot.name) · \(Format.distance(distance)) away"
        case .prohibited(let hit, _, _):
            symbol = "nosign"
            tint = Brand.danger
            title = hit.isCertain ? "No smoking here" : "Probably no smoking here"
            subtitle = hit.zone.title
        case .nearZone(let hit):
            symbol = "exclamationmark"
            tint = Brand.warning
            title = "Near a no-smoking zone"
            subtitle = "\(hit.zone.title), \(Format.distance(max(0, hit.signedDistance))) away. Your GPS can't tell for sure."
        case .clear:
            symbol = "hand.thumbsup.fill"
            tint = Brand.allowed
            title = "No known restriction"
            subtitle = "Outdoors, away from shelters and entrances: generally fine."
        }
    }
}

/// "Can I smoke here?" in one glance: a coloured disc, a short verdict, a line of context.
/// Tap to unfold the rule, the other zones around and the fine; swipe up to minimise it.
struct StatusCard: View {
    let verdict: Verdict
    let locationDenied: Bool
    var onShowExit: () -> Void = {}
    var onMinimize: () -> Void = {}

    @State private var expanded = false

    var body: some View {
        let summary = VerdictSummary(verdict, locationDenied: locationDenied)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    guard hasDetails else { return }
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        IconCircle(symbol: summary.symbol, tint: summary.tint, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(summary.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if hasDetails {
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(.tertiary)
                                        .rotationEffect(.degrees(expanded ? 180 : 0))
                                }
                            }
                            if let subtitle = summary.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(expanded ? nil : 2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(hasDetails ? (expanded ? "Hides the details" : "Shows the details") : "")

                Button(action: onMinimize) {
                    Image(systemName: "chevron.up")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimise the status card")
            }

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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 24)
        .onVerticalSwipe(.top, perform: onMinimize)
    }

    // MARK: Details per verdict

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
