import MapKit
import SingaSmokeCore
import SwiftUI

/// Today's status, the week's hours and where they come from, in a shop's details.
struct ShopHoursBlock: View {
    let retailer: Retailer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(status?.tint ?? .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                if let hours = retailer.hours, let status {
                    Text(Format.opening(status))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(status.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(hours.schedule.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(line.days)
                                    .frame(width: 84, alignment: .leading)
                                Text(line.hours)
                            }
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    Text("Hours from OpenStreetMap: they can change. Apple Maps may know better.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Opening hours")
                        .font(.subheadline.weight(.bold))
                    Text(retailer.hoursText ?? "Not listed for this shop.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AppleMapsHoursButton(retailer: retailer)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.tertiarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var status: OpeningStatus? { retailer.hours?.status(at: .now) }
}

/// Finds the shop on Apple Maps and shows its place card (live hours, phone, photos): inside the
/// app from iOS 18, in Apple Maps before that, or an Apple Maps search when no place matches.
struct AppleMapsHoursButton: View {
    let retailer: Retailer
    @Environment(\.openURL) private var openURL
    @State private var searching = false
    @State private var place: MKMapItem?

    var body: some View {
        Button {
            Task { await open() }
        } label: {
            HStack(spacing: 6) {
                if searching {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "map.fill")
                }
                Text("Hours on Apple Maps")
            }
        }
        .buttonStyle(.pill(.secondary, compact: true))
        .disabled(searching)
        .modifier(PlaceCardSheet(item: $place))
    }

    private func open() async {
        searching = true
        defer { searching = false }
        guard let item = await AppleMapsPlace.find(retailer) else {
            openURL(AppleMapsPlace.searchURL(retailer))
            return
        }
        if #available(iOS 18.0, *) {
            place = item
        } else {
            _ = item.openInMaps(launchOptions: nil)
        }
    }
}

/// Apple's place card, presented over the sheet (iOS 18 and later).
private struct PlaceCardSheet: ViewModifier {
    @Binding var item: MKMapItem?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.mapItemDetailSheet(item: $item, displaysMap: true)
        } else {
            content
        }
    }
}

@MainActor
enum AppleMapsPlace {
    /// The Apple Maps place for a licensed shop: its brand or name, within 150 m of its building.
    static func find(_ retailer: Retailer) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = retailer.brand ?? retailer.name
        request.region = MKCoordinateRegion(center: retailer.coordinate.cl, latitudinalMeters: 500, longitudinalMeters: 500)
        request.resultTypes = .pointOfInterest
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        let building = CLLocation(latitude: retailer.coordinate.latitude, longitude: retailer.coordinate.longitude)
        var best: (item: MKMapItem, distance: CLLocationDistance)?
        for item in response.mapItems {
            guard let location = item.placemark.location else { continue }
            let distance = location.distance(from: building)
            if distance <= 150, distance < (best?.distance ?? .infinity) { best = (item, distance) }
        }
        return best?.item
    }

    /// Apple Maps searching for the shop around its building.
    static func searchURL(_ retailer: Retailer) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: retailer.brand ?? retailer.name),
            URLQueryItem(name: "sll", value: "\(retailer.coordinate.latitude),\(retailer.coordinate.longitude)"),
            URLQueryItem(name: "z", value: "18"),
        ]
        return components.url!
    }
}

extension OpeningStatus {
    /// Green when open, orange in the last half hour, red when closed.
    var tint: Color {
        switch self {
        case .alwaysOpen: return Brand.allowed
        case .open(let left, _): return left <= 30 ? Brand.warning : Brand.allowed
        case .closed, .closedAllWeek: return Brand.danger
        }
    }
}
