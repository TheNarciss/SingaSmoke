import SingaSmokeCore
import SwiftUI

/// How to read the app, how far to trust it, and where everything comes from.
struct AboutTab: View {
    @Environment(AppModel.self) private var model
    @State private var showDisclaimer = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Legal.signage)
                        .font(.headline)
                    Text("Les données peuvent être périmées : un spot peut avoir disparu, une zone avoir changé. SingaSmoke aide à s'orienter, il ne remplace pas les panneaux.")
                    Button("Relire l'avertissement") { showDisclaimer = true }
                } header: {
                    Text("Avant tout")
                }

                Section("Le bandeau") {
                    legendRow("nosign", .red, "Zone interdite", "Tu es dans un lieu non-fumeur connu. L'app indique la sortie et le spot le plus proche.")
                    legendRow("exclamationmark.triangle.fill", .orange, "Limite de zone", "Une zone commence dans la marge d'erreur de ton GPS.")
                    legendRow("checkmark.circle.fill", .green, "Zone fumeur", "Tu es sur un carré jaune NEA ou un coin fumeur signalé.")
                    legendRow("checkmark.circle", .teal, "Zone OK", "Aucune interdiction connue ici. En plein air, hors abri, loin des entrées : en principe autorisé.")
                }

                Section {
                    reliabilityRow(.official, "NEA : carrés jaunes d'Orchard Road, zone non-fumeur d'Orchard, hawker centres.")
                    reliabilityRow(.official, "NParks : parcs et jardins non-fumeurs.")
                    reliabilityRow(.official, "Changi Airport Group : zones fumeurs de l'aéroport. Décrites en mots, donc placées à la porte citée ou au terminal : position approximative.")
                    reliabilityRow(.official, "HSA : registre des points de vente. Position au bâtiment du code postal.")
                    reliabilityRow(.indicative, "OpenStreetMap : coins fumeurs, arrêts de bus, aires de jeux, terrains, écoles, hôpitaux… Complet par endroits, lacunaire ailleurs.")
                } header: {
                    Text("Fiabilité des sources")
                } footer: {
                    Text("Sur la carte, les zones officielles ont un contour plein, celles d'OpenStreetMap un contour pointillé.")
                }

                Section {
                    ForEach(ZoneKind.allCases.filter { $0 != .other }, id: \.self) { kind in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.label).font(.subheadline.weight(.semibold))
                                Text(kind.rule).font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: kind.symbol).foregroundStyle(.red)
                        }
                    }
                    Label(Legal.unmapped, systemImage: "eye.slash")
                        .font(.footnote)
                } header: {
                    Text("Où c'est interdit à Singapour")
                } footer: {
                    Text("\(Legal.fine) \(Legal.vape)")
                }

                Section("Données") {
                    if let meta = model.data?.meta {
                        LabeledContent("Générées le", value: Format.date(meta.generated) ?? meta.generated)
                        ForEach(meta.sources) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name).font(.subheadline.weight(.semibold))
                                Text([source.publisher, Format.date(source.updated).map { "mis à jour le \($0)" }, source.licence]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let data = model.data {
                        LabeledContent("Spots fumeurs", value: "\(data.spots.count)")
                        LabeledContent("Lieux non-fumeurs", value: "\(data.zones.count)")
                        LabeledContent("Points de vente", value: "\(data.retailers.count)")
                    }
                }

                Section("Vie privée") {
                    Label("Ta position n'est utilisée que quand l'app est ouverte, sur le téléphone.", systemImage: "location")
                    Label("Aucun compte, aucun suivi, aucune statistique, rien n'est envoyé à SingaSmoke.", systemImage: "hand.raised")
                    Label("Le réseau sert au fond de carte et aux itinéraires d'Apple, et aux photos NEA. Le verdict et les listes marchent hors ligne.", systemImage: "wifi")
                }

                Section {
                    Text("Contains information from the Designated Smoking Areas, No-Smoking Zones, Hawker Centres, NParks No-Smoking Locations and Listing of Licensed Tobacco Retailers datasets accessed from data.gov.sg, made available under the terms of the Singapore Open Data Licence version 1.0.")
                    Text("© OpenStreetMap contributors, données sous licence ODbL.")
                    Text("Géocodage : OneMap © Singapore Land Authority. Zones fumeurs de Changi : Changi Airport Group.")
                    Text("Application non officielle, sans lien avec NEA, NParks, HSA, SLA ni Changi Airport Group. Traitement des données inspiré de smokingarea-sg (MIT).")
                    Link("Code source sur GitHub", destination: URL(string: "https://github.com/TheNarciss/SingaSmoke")!)
                } header: {
                    Text("Licences et attributions")
                }
                .font(.footnote)
            }
            .navigationTitle("Infos")
            .sheet(isPresented: $showDisclaimer) {
                DisclaimerSheet(onAccept: { showDisclaimer = false })
            }
        }
    }

    private func legendRow(_ symbol: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }

    private func reliabilityRow(_ reliability: Reliability, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ReliabilityBadge(reliability: reliability)
            Text(text).font(.footnote)
        }
    }
}

/// Shown at first launch, and on demand from the Infos tab.
struct DisclaimerSheet: View {
    var onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Avant de commencer")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    point("signpost.right.fill", Legal.signage)
                    point("clock.arrow.circlepath", "Les données viennent de sources publiques (NEA, NParks, HSA, Changi Airport, OpenStreetMap) et peuvent être périmées ou incomplètes.")
                    point("eye.slash", Legal.unmapped)
                    point("banknote", Legal.fine)
                    point("nosign", Legal.vape)
                    point("location", "La localisation ne sert que quand l'app est ouverte. Rien n'est collecté ni envoyé.")
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onAccept) {
                    Text("J'ai compris")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .background(.bar)
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
        .font(.body)
    }
}
