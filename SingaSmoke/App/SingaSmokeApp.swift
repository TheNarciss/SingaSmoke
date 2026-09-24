import SingaSmokeCore
import SwiftUI

@main
struct SingaSmokeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.load() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Bumped if the disclaimer ever changes and must be read again.
    @AppStorage("acceptedDisclaimerVersion") private var acceptedDisclaimer = 0
    private let disclaimerVersion = 2

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("Loading data…")
            case .failed(let message):
                ContentUnavailableView("Unreadable data", systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready:
                TabView {
                    SmokeTab()
                        .tabItem { Label("Smoke", systemImage: "smoke") }
                    BuyTab()
                        .tabItem { Label("Buy", systemImage: "cart") }
                    AboutTab()
                        .tabItem { Label("Info", systemImage: "info.circle") }
                }
            }
        }
        .sheet(isPresented: disclaimerPending) {
            DisclaimerSheet(onAccept: {
                acceptedDisclaimer = disclaimerVersion
                model.location.start()
            })
            .interactiveDismissDisabled()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active where acceptedDisclaimer >= disclaimerVersion:
                model.location.start()
            case .background:
                model.location.stop()
            default:
                break
            }
        }
        .onChange(of: model.location.fix) { _, _ in
            model.locationChanged()
        }
    }

    private var disclaimerPending: Binding<Bool> {
        Binding(
            get: { acceptedDisclaimer < disclaimerVersion },
            set: { _ in }
        )
    }
}
