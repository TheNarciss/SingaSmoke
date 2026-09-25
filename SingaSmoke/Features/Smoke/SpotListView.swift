import SingaSmokeCore
import SwiftUI

/// Every nearby spot, nearest first by walking distance. Opened from the list button.
struct SpotListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var officialOnly = false
    var onGo: (SmokingSpot) -> Void

    var body: some View {
        List {
            Section {
                Toggle(isOn: $officialOnly) {
                    Label("Official sources only", systemImage: Reliability.official.symbol)
                }
                .tint(Brand.allowed)
            } footer: {
                Text(model.referenceIsUser
                     ? "Walking times come from Apple Maps when online; \"≈\" marks an estimate."
                     : "Without your location, distances are measured from the centre of the map.")
            }
            Section {
                ForEach(places) { place in
                    NavigationLink {
                        SpotDetailView(spot: place.item, onGo: { onGo(place.item) })
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        PlaceRow(symbol: place.item.glyph, tint: place.item.tint, title: place.item.name,
                                 subtitle: place.item.details, walking: place.walking, caveat: place.item.caveat)
                    }
                }
            }
        }
        .navigationTitle("Smoking spots")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var places: [RankedPlace<SmokingSpot>] {
        officialOnly ? model.nearestSpots.filter { $0.item.reliability == .official } : model.nearestSpots
    }
}
