import MapKit
import SingaSmokeCore
import SwiftUI

/// Licensed tobacco retailers (HSA register), filterable by kind of shop.
struct BuyTab: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Retailer?
    @State private var guidance: GuidanceTarget?
    @State private var pendingGuidance: GuidanceTarget?
    @State private var recenter = 0
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                SingaMapView(
                    retailers: model.filteredRetailers,
                    recenterToken: recenter,
                    onSelectRetailer: { selected = $0 },
                    onRegionChange: { model.mapCentreChanged(Coordinate($0.center)) }
                )
                .ignoresSafeArea(edges: .top)
                .accessibilityLabel("Carte des points de vente de tabac")

                VStack(spacing: 10) {
                    CategoryFilter()
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        MapButton(symbol: "location.fill", label: "Me recentrer") { recenter += 1 }
                    }
                    NearestRetailersCard(places: Array(model.nearestRetailers.prefix(3)),
                                         referenceIsUser: model.referenceIsUser,
                                         onSelect: { selected = $0 },
                                         onShowAll: { path.append(RetailerListRoute()) })
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RetailerListRoute.self) { _ in
                RetailerListView(onGo: { guidance = GuidanceTarget(retailer: $0) })
            }
        }
        .sheet(item: $selected, onDismiss: {
            if let target = pendingGuidance { pendingGuidance = nil; guidance = target }
        }) { shop in
            NavigationStack {
                RetailerDetailView(retailer: shop, onGo: {
                    pendingGuidance = GuidanceTarget(retailer: shop)
                    selected = nil
                })
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(model)
        }
        .fullScreenCover(item: $guidance) { target in
            GuidanceView(target: target)
                .environment(model)
        }
    }
}

struct RetailerListRoute: Hashable {}

/// Chips to show or hide each kind of shop.
struct CategoryFilter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RetailCategory.allCases) { category in
                    let on = model.retailerCategories.contains(category)
                    Button {
                        if on {
                            if model.retailerCategories.count > 1 { model.retailerCategories.remove(category) }
                        } else {
                            model.retailerCategories.insert(category)
                        }
                    } label: {
                        Label(category.label, systemImage: category.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(on ? .white : .primary)
                            .background(on ? category.color : Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityHint(on ? "Masque cette catégorie" : "Affiche cette catégorie")
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NearestRetailersCard: View {
    let places: [RankedPlace<Retailer>]
    let referenceIsUser: Bool
    let onSelect: (Retailer) -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(referenceIsUser ? "Points de vente les plus proches" : "Proches du centre de la carte")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Tout voir", action: onShowAll)
                    .font(.subheadline)
            }
            ForEach(places) { place in
                Button {
                    onSelect(place.item)
                } label: {
                    PlaceRow(symbol: place.item.category.symbol, tint: place.item.category.color,
                             title: place.item.name, subtitle: place.item.category.label, walking: place.walking)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre la fiche")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct RetailerListView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Retailer?
    @State private var pending: Retailer?
    var onGo: (Retailer) -> Void

    var body: some View {
        List {
            Section {
                ForEach(model.nearestRetailers) { place in
                    Button {
                        selected = place.item
                    } label: {
                        PlaceRow(symbol: place.item.category.symbol, tint: place.item.category.color,
                                 title: place.item.name, subtitle: place.item.address, walking: place.walking)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Registre HSA des licences de vente de tabac. Position au bâtiment (code postal), sans horaires d'ouverture. \(Legal.vape)")
            }
        }
        .navigationTitle("Points de vente")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected, onDismiss: {
            if let shop = pending { pending = nil; onGo(shop) }
        }) { shop in
            NavigationStack {
                RetailerDetailView(retailer: shop, onGo: {
                    pending = shop
                    selected = nil
                })
            }
            .presentationDetents([.medium, .large])
            .environment(model)
        }
    }
}

struct RetailerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let retailer: Retailer
    var onGo: () -> Void

    @State private var walking: WalkingDistance?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(retailer.name)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Label(retailer.category.label, systemImage: retailer.category.symbol)
                        .foregroundStyle(retailer.category.color)
                    ReliabilityBadge(reliability: .official)
                }
                .padding(.vertical, 4)
                LabeledContent("Adresse") {
                    Text(retailer.address).multilineTextAlignment(.trailing)
                }
                if let building = retailer.building {
                    LabeledContent("Bâtiment", value: building)
                }
                if let licensee = retailer.licensee {
                    LabeledContent("Titulaire de la licence") {
                        Text(licensee).multilineTextAlignment(.trailing)
                    }
                }
                if let validity = retailer.validity {
                    LabeledContent("Licence", value: validity)
                }
                LabeledContent("Distance") {
                    Text(Format.walking(walking ?? estimate)).monospacedDigit()
                }
            } footer: {
                Text("Position au bâtiment du code postal : dans un centre commercial, cherche la boutique sur place.")
            }

            Section {
                Button(action: onGo) {
                    Label("Itinéraire à pied dans l'app", systemImage: "figure.walk")
                        .font(.headline)
                }
                Button {
                    ExternalMaps.openInAppleMaps(retailer.coordinate, name: retailer.name)
                } label: {
                    Label("Ouvrir dans Plans", systemImage: "map")
                }
                Button {
                    openURL(ExternalMaps.googleMapsURL(retailer.coordinate))
                } label: {
                    Label("Ouvrir dans Google Maps", systemImage: "globe")
                }
            } footer: {
                Text(Legal.vape)
            }
        }
        .navigationTitle(retailer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { dismiss() }
            }
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
