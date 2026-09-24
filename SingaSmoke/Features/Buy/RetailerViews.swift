import SingaSmokeCore
import SwiftUI

/// The nearest licensed retailers of the categories shown on the map.
struct RetailerListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onGo: (Retailer) -> Void

    var body: some View {
        List {
            Section {
                ForEach(model.nearestRetailers) { place in
                    NavigationLink {
                        RetailerDetailView(retailer: place.item, onGo: { onGo(place.item) })
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        PlaceRow(symbol: place.item.category.symbol, tint: place.item.category.color,
                                 title: place.item.name, subtitle: place.item.address, walking: place.walking)
                    }
                }
            } footer: {
                Text("HSA register of licensed tobacco retailers, located to the building of their postal code. No opening hours. \(Legal.vape)")
            }
        }
        .navigationTitle("Shops")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

/// One licensed retailer.
struct RetailerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let retailer: Retailer
    var onGo: () -> Void

    @State private var walking: WalkingDistance?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    IconCircle(symbol: retailer.category.symbol, tint: retailer.category.color, size: 54)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(retailer.name)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(retailer.category.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Chip(text: (walking ?? estimate).chipText, symbol: "figure.walk", tint: .primary)
                            Chip(text: "Licensed", symbol: Reliability.official.symbol, tint: Brand.allowed)
                        }
                    }
                }

                InfoBlock(symbol: "mappin.and.ellipse", title: retailer.building ?? "Address",
                          text: "\(retailer.address)\n\nLocated to the building of its postal code: in a mall, look for the shop on site.")

                VStack(spacing: 10) {
                    Button(action: onGo) {
                        Label("Start walking", systemImage: "figure.walk")
                    }
                    .buttonStyle(.pill)
                    HStack(spacing: 10) {
                        Button {
                            ExternalMaps.openInAppleMaps(retailer.coordinate, name: retailer.name)
                        } label: {
                            Label("Apple Maps", systemImage: "map.fill")
                        }
                        .buttonStyle(.pill(.secondary))
                        Button {
                            openURL(ExternalMaps.googleMapsURL(retailer.coordinate))
                        } label: {
                            Label("Google Maps", systemImage: "globe")
                        }
                        .buttonStyle(.pill(.secondary))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let licensee = retailer.licensee { Text("Licensee: \(licensee)") }
                    if let validity = retailer.validity { Text("Licence period: \(validity)") }
                    Text("Source: Health Sciences Authority (HSA)")
                    Text(Legal.vape)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .task(id: retailer.id) {
            guard model.referenceIsUser else { return }
            walking = await WalkingRouter.walkingETA(from: model.reference, to: retailer.coordinate)
        }
    }

    private var estimate: WalkingDistance {
        .estimate(straightLine: Geo.distance(model.reference, retailer.coordinate))
    }
}
