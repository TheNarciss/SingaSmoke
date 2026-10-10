import MapKit
import SingaSmokeCore
import SwiftUI

enum AppMode: String, CaseIterable, Identifiable {
    case smoke
    case buy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smoke: return "Smoking areas"
        case .buy: return "Where to buy"
        }
    }

    var symbol: String {
        switch self {
        case .smoke: return "smoke.fill"
        case .buy: return "bag.fill"
        }
    }
}

/// One screen laid out like a maps app: the map everywhere, a slim status bar and two chips on top,
/// a bottom sheet that stays folded on the nearest place until it is pulled up or a place is picked.
struct HomeView: View {
    /// Folded sheet: the nearest place and its Go button, nothing more (plus the home indicator's area).
    static let folded = PresentationDetent.height(92)

    @Environment(AppModel.self) private var model
    @State private var mode: AppMode = .smoke
    @State private var selection: SelectedPlace?
    @State private var detent: PresentationDetent = HomeView.folded
    @State private var statusExpanded = false
    @State private var guidance: GuidanceTarget?
    @State private var showInfo = false
    @State private var showExit = false
    @State private var recenter = 0
    /// Top of the sheet, in window coordinates: Apple's logo and "Legal" link go just above it.
    @State private var sheetTop: CGFloat?

    var body: some View {
        GeometryReader { screen in
            let screenBottom = screen.frame(in: .global).maxY + screen.safeAreaInsets.bottom
            ZStack(alignment: .top) {
                SingaMapView(
                    spots: mode == .smoke ? (model.data?.spots ?? []) : [],
                    retailers: mode == .buy ? model.filteredRetailers : [],
                    zoneIndex: mode == .smoke ? model.data?.zoneIndex : nil,
                    marker: exitMarker,
                    recenterToken: recenter,
                    attributionInset: attributionInset(screenBottom: screenBottom, safeBottom: screen.safeAreaInsets.bottom,
                                                       screenHeight: screen.size.height),
                    onSelectSpot: { select(.spot($0)) },
                    onSelectRetailer: { select(.shop($0)) },
                    onRegionChange: { model.mapCentreChanged(Coordinate($0.center)) },
                    onUserGesture: mapTouched
                )
                .ignoresSafeArea()
                .accessibilityLabel(mode == .smoke ? "Map of smoking and no-smoking areas" : "Map of licensed tobacco retailers")

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusBar(verdict: model.verdict, locationDenied: model.location.isDenied,
                                  expanded: $statusExpanded,
                                  onShowExit: {
                                      showExit = true
                                      recenter += 1
                                      withAnimation(.snappy) { statusExpanded = false }
                                  })
                        ModeChips(mode: $mode)
                    }
                    MapControls(onInfo: { showInfo = true }, onLocate: { recenter += 1 })
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
        .onChange(of: mode) { _, _ in
            selection = nil
        }
        .onChange(of: model.verdictIsProhibited) { _, prohibited in
            if !prohibited { showExit = false }
        }
        .sheet(isPresented: .constant(true)) {
            HomeSheet(mode: mode, folded: detent == Self.folded, selection: selection,
                      onSelect: select,
                      onClose: {
                          selection = nil
                          detent = Self.folded
                      },
                      onGo: { guidance = $0 })
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { sheetTop = proxy.frame(in: .global).minY }
                            .onChange(of: proxy.frame(in: .global).minY) { _, top in sheetTop = top }
                    }
                }
                .presentationDetents([Self.folded, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Brand.sheet)
                .interactiveDismissDisabled()
                // Presented from the sheet: the map screen already has the sheet as its one presentation.
                .sheet(isPresented: $showInfo) {
                    InfoView()
                        .presentationBackground(Brand.groupedSheet)
                        .environment(model)
                }
                .fullScreenCover(item: $guidance) { target in
                    GuidanceView(target: target)
                        .environment(model)
                }
                .environment(model)
        }
        #if DEBUG
        .task { await applyScreenshotArguments() }
        #endif
    }

    // MARK: Interaction

    private func select(_ place: SelectedPlace) {
        selection = place
        if detent == Self.folded { detent = .medium }
    }

    /// The map moved under the user's finger: fold everything so the map gets the screen back.
    private func mapTouched() {
        if statusExpanded { withAnimation(.snappy) { statusExpanded = false } }
        if detent == .medium { detent = Self.folded }
    }

    private var exitMarker: MarkerAnnotation? {
        guard showExit, case .prohibited(let hit, _, _) = model.verdict else { return nil }
        return MarkerAnnotation(.exit, coordinate: hit.exit, title: "Way out of the zone")
    }

    /// From the bottom safe area up to just above the sheet, never past the middle of the screen.
    private func attributionInset(screenBottom: CGFloat, safeBottom: CGFloat, screenHeight: CGFloat) -> CGFloat {
        guard let sheetTop, sheetTop.isFinite else { return 0 }
        let covered = screenBottom - sheetTop - safeBottom
        return max(0, min(covered + 6, screenHeight * 0.5))
    }

    #if DEBUG
    /// Launch arguments used by CI to capture screenshots: -uiMode buy, -uiExpandStatus YES,
    /// -uiOpenFirstSpot YES, -uiShowList YES, -uiGuideFirstSpot YES, -uiShowInfo YES.
    private func applyScreenshotArguments() async {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "uiMode") == "buy" { mode = .buy }
        if defaults.bool(forKey: "uiExpandStatus") { statusExpanded = true }
        let wanted = ["uiOpenFirstSpot", "uiShowList", "uiGuideFirstSpot", "uiShowInfo"].filter { defaults.bool(forKey: $0) }
        guard !wanted.isEmpty else { return }
        try? await Task.sleep(for: .seconds(6))
        let first = model.nearestSpots.first?.item
        if wanted.contains("uiOpenFirstSpot"), let first { select(.spot(first)) }
        if wanted.contains("uiShowList") { detent = .medium }
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

/// Smoking areas / Where to buy, as two chips under the status bar.
struct ModeChips: View {
    @Binding var mode: AppMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppMode.allCases) { item in
                let on = item == mode
                Button {
                    withAnimation(.snappy) { mode = item }
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.footnote.weight(.bold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(on ? Brand.onInk : .primary)
                        .background(on ? Brand.ink : Brand.card, in: Capsule())
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Info and recentre stacked in one small capsule, top right, as in Apple Maps.
struct MapControls: View {
    let onInfo: () -> Void
    let onLocate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            control("info", label: "About SingaSmoke", action: onInfo)
            Divider().frame(width: 26)
            control("location.fill", label: "Centre on my location", action: onLocate)
        }
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }

    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
