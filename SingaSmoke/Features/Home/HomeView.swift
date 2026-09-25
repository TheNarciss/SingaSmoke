import MapKit
import SingaSmokeCore
import SwiftUI

enum AppMode: String, CaseIterable, Identifiable {
    case smoke
    case buy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smoke: return "Smoke"
        case .buy: return "Buy"
        }
    }

    var symbol: String {
        switch self {
        case .smoke: return "smoke.fill"
        case .buy: return "bag.fill"
        }
    }
}

/// One screen, map first: where you can smoke (or buy), what the rule is here, and the nearest options.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: AppMode = .smoke
    @State private var selectedSpot: SmokingSpot?
    @State private var selectedShop: Retailer?
    @State private var guidance: GuidanceTarget?
    /// Guidance asked from a sheet: shown once the sheet is gone (two modals cannot overlap).
    @State private var pendingGuidance: GuidanceTarget?
    @State private var recenter = 0
    @State private var showExit = false
    @State private var showList = false
    @State private var showInfo = false
    /// Cards minimised to leave the map room: the status card (or the shop filters) at the top,
    /// the nearby cards at the bottom. Dragging or pinching the map minimises both.
    @State private var topMinimized = false
    @State private var bottomMinimized = false

    var body: some View {
        ZStack(alignment: .top) {
            SingaMapView(
                spots: mode == .smoke ? (model.data?.spots ?? []) : [],
                retailers: mode == .buy ? model.filteredRetailers : [],
                zoneIndex: mode == .smoke ? model.data?.zoneIndex : nil,
                marker: exitMarker,
                recenterToken: recenter,
                onSelectSpot: { selectedSpot = $0 },
                onSelectRetailer: { selectedShop = $0 },
                onRegionChange: { model.mapCentreChanged(Coordinate($0.center)) },
                onUserGesture: { setMinimized(true) }
            )
            .ignoresSafeArea()
            .accessibilityLabel(mode == .smoke ? "Map of smoking and no-smoking areas" : "Map of licensed tobacco retailers")

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ModePicker(mode: $mode)
                        Spacer(minLength: 0)
                        FloatingButton(symbol: "info", label: "About SingaSmoke", size: 44) { showInfo = true }
                    }
                    topPanel
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 12) {
                    if bottomMinimized {
                        nearbyPill
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 12) {
                        FloatingButton(symbol: allMinimized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                       label: allMinimized ? "Show the cards" : "Full-screen map") {
                            setMinimized(!allMinimized)
                        }
                        FloatingButton(symbol: "list.bullet", label: mode == .smoke ? "All smoking spots" : "All shops") { showList = true }
                        FloatingButton(symbol: "location.fill", label: "Centre on my location") { recenter += 1 }
                    }
                }
                .padding(.horizontal, 16)

                if !bottomMinimized {
                    NearbyCarousel(mode: mode,
                                   spots: Array(model.nearestSpots.prefix(8)),
                                   shops: Array(model.nearestRetailers.prefix(8)),
                                   referenceIsUser: model.referenceIsUser,
                                   onOpenSpot: { selectedSpot = $0 },
                                   onOpenShop: { selectedShop = $0 },
                                   onGo: { guidance = $0 })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 8)
        }
        .animation(.snappy, value: mode)
        .sensoryFeedback(.selection, trigger: mode)
        .sheet(item: $selectedSpot, onDismiss: startPendingGuidance) { spot in
            SpotDetailView(spot: spot, onGo: {
                pendingGuidance = GuidanceTarget(spot: spot)
                selectedSpot = nil
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .presentationBackground(Brand.sheet)
            .environment(model)
        }
        .sheet(item: $selectedShop, onDismiss: startPendingGuidance) { shop in
            RetailerDetailView(retailer: shop, onGo: {
                pendingGuidance = GuidanceTarget(retailer: shop)
                selectedShop = nil
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .presentationBackground(Brand.sheet)
            .environment(model)
        }
        .sheet(isPresented: $showList, onDismiss: startPendingGuidance) {
            NavigationStack {
                if mode == .smoke {
                    SpotListView(onGo: { spot in
                        pendingGuidance = GuidanceTarget(spot: spot)
                        showList = false
                    })
                } else {
                    RetailerListView(onGo: { shop in
                        pendingGuidance = GuidanceTarget(retailer: shop)
                        showList = false
                    })
                }
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(32)
            .presentationBackground(Brand.groupedSheet)
            .environment(model)
        }
        .sheet(isPresented: $showInfo) {
            InfoView()
                .presentationCornerRadius(32)
                .presentationBackground(Brand.groupedSheet)
                .environment(model)
        }
        .fullScreenCover(item: $guidance) { target in
            GuidanceView(target: target)
                .environment(model)
        }
        .onChange(of: model.verdictIsProhibited) { _, prohibited in
            if !prohibited { showExit = false }
        }
        #if DEBUG
        .task { await applyScreenshotArguments() }
        #endif
    }

    // MARK: Minimised cards

    private var allMinimized: Bool { topMinimized && bottomMinimized }

    private func setMinimized(_ minimized: Bool) {
        guard topMinimized != minimized || bottomMinimized != minimized else { return }
        withAnimation(.snappy) {
            topMinimized = minimized
            bottomMinimized = minimized
        }
    }

    /// The status card or, in Buy mode, the shop filters; a small pill when minimised.
    @ViewBuilder
    private var topPanel: some View {
        switch (mode, topMinimized) {
        case (.smoke, false):
            StatusCard(verdict: model.verdict, locationDenied: model.location.isDenied,
                       onShowExit: { showExit = true; recenter += 1 },
                       onMinimize: { withAnimation(.snappy) { topMinimized = true } })
                .transition(.move(edge: .top).combined(with: .opacity))
        case (.smoke, true):
            let summary = VerdictSummary(model.verdict, locationDenied: model.location.isDenied)
            CompactPill(symbol: summary.symbol, tint: summary.tint, title: summary.title) {
                withAnimation(.snappy) { topMinimized = false }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        case (.buy, false):
            CategoryChips()
                .onVerticalSwipe(.top) { withAnimation(.snappy) { topMinimized = true } }
                .transition(.move(edge: .top).combined(with: .opacity))
        case (.buy, true):
            let shown = model.retailerCategories.count
            CompactPill(symbol: "line.3.horizontal.decrease", tint: Brand.accent, title: "Shop types",
                        detail: shown == RetailCategory.allCases.count ? "All shown" : "\(shown) of \(RetailCategory.allCases.count) shown") {
                withAnimation(.snappy) { topMinimized = false }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// The nearest place in one line, standing in for the minimised cards.
    private var nearbyPill: some View {
        let restore = { withAnimation(.snappy) { bottomMinimized = false } }
        return Group {
            switch mode {
            case .smoke:
                if let place = model.nearestSpots.first {
                    CompactPill(symbol: place.item.glyph, tint: place.item.tint, title: place.item.name,
                                detail: place.walking.chipText, chevron: "chevron.up", action: restore)
                } else {
                    CompactPill(symbol: "mappin.and.ellipse", tint: Brand.allowed, title: "Nearby spots",
                                chevron: "chevron.up", action: restore)
                }
            case .buy:
                if let place = model.nearestRetailers.first {
                    CompactPill(symbol: place.item.category.symbol, tint: place.item.category.color, title: place.item.name,
                                detail: place.walking.chipText, chevron: "chevron.up", action: restore)
                } else {
                    CompactPill(symbol: "bag.fill", tint: .gray, title: "Nearby shops",
                                chevron: "chevron.up", action: restore)
                }
            }
        }
    }

    private func startPendingGuidance() {
        guard let pending = pendingGuidance else { return }
        pendingGuidance = nil
        guidance = pending
    }

    private var exitMarker: MarkerAnnotation? {
        guard showExit, case .prohibited(let hit, _, _) = model.verdict else { return nil }
        return MarkerAnnotation(.exit, coordinate: hit.exit, title: "Way out of the zone")
    }

    #if DEBUG
    /// Launch arguments used by CI to capture screenshots:
    /// -uiMode buy, -uiMinimize YES, -uiOpenFirstSpot YES, -uiShowList YES, -uiGuideFirstSpot YES, -uiShowInfo YES.
    private func applyScreenshotArguments() async {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "uiMode") == "buy" { mode = .buy }
        if defaults.bool(forKey: "uiMinimize") { topMinimized = true; bottomMinimized = true }
        let wanted = ["uiOpenFirstSpot", "uiShowList", "uiGuideFirstSpot", "uiShowInfo"].filter { defaults.bool(forKey: $0) }
        guard !wanted.isEmpty else { return }
        try? await Task.sleep(for: .seconds(6))
        let first = model.nearestSpots.first?.item
        if wanted.contains("uiOpenFirstSpot") { selectedSpot = first }
        if wanted.contains("uiShowList") { showList = true }
        if wanted.contains("uiShowInfo") { showInfo = true }
        if wanted.contains("uiGuideFirstSpot"), let first { guidance = GuidanceTarget(spot: first) }
    }
    #endif
}

extension AppModel {
    var verdictIsProhibited: Bool {
        if case .prohibited = verdict { return true }
        return false
    }
}

/// Smoke / Buy, as a capsule with a sliding black pill.
struct ModePicker: View {
    @Binding var mode: AppMode
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppMode.allCases) { item in
                let on = item == mode
                Button {
                    mode = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .foregroundStyle(on ? Brand.onInk : .primary)
                        .background {
                            if on {
                                Capsule().fill(Brand.ink).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Brand.card, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }
}
