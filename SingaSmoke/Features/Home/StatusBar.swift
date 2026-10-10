import SingaSmokeCore
import SwiftUI
import UIKit

/// What the app says about where the user stands: an icon, a colour, a title, a line of context.
/// Shared by the status bar and anything else that sums up the verdict.
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

/// "Can I smoke here?" as one slim bar at the top of the map, where a maps app puts its search field.
/// Tap it to unfold the rule, the zones around and the fine; it folds back when the map moves.
struct StatusBar: View {
    let verdict: Verdict
    let locationDenied: Bool
    @Binding var expanded: Bool
    var onShowExit: () -> Void = {}

    var body: some View {
        let summary = VerdictSummary(verdict, locationDenied: locationDenied)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        IconCircle(symbol: summary.symbol, tint: summary.tint, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(summary.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if expanded, let subtitle = summary.subtitle {
                                Text(subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(expanded ? "Hides the details" : "Shows the details")

                // Folded inside a zone, the way out stays one tap away.
                if !expanded, case .prohibited(let hit, _, _) = verdict {
                    Button(action: onShowExit) {
                        Label(Format.distance(hit.exitDistance), systemImage: "figure.walk")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(.white)
                            .background(Brand.danger, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Way out, \(Format.distance(hit.exitDistance)) \(hit.exitDirection.rawValue)")
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(minHeight: 48)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
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
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
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
}
