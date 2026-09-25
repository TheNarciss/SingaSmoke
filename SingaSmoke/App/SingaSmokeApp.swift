import SingaSmokeCore
import SwiftUI

@main
struct SingaSmokeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .fontDesign(.rounded)
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
                VStack(spacing: 18) {
                    Logo(size: 88)
                    ProgressView()
                }
            case .failed(let message):
                ContentUnavailableView("Unreadable data", systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready:
                HomeView()
            }
        }
        .sheet(isPresented: disclaimerPending) {
            DisclaimerSheet(onAccept: {
                acceptedDisclaimer = disclaimerVersion
                model.location.start()
            })
            .presentationBackground(Brand.sheet)
            .interactiveDismissDisabled()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active where disclaimerAccepted:
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

    private var disclaimerAccepted: Bool {
        #if DEBUG
        // CI screenshots launch with -uiSkipDisclaimer YES.
        if UserDefaults.standard.bool(forKey: "uiSkipDisclaimer") { return true }
        #endif
        return acceptedDisclaimer >= disclaimerVersion
    }

    private var disclaimerPending: Binding<Bool> {
        Binding(
            get: { !disclaimerAccepted },
            set: { _ in }
        )
    }
}
