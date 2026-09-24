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
                    Text("The data can be out of date: a spot may be gone, a zone may have changed. SingaSmoke helps you find your way; it doesn't replace the signs.")
                    Button("Read the warning again") { showDisclaimer = true }
                } header: {
                    Text("First things first")
                }

                Section("The banner") {
                    legendRow("nosign", .red, "No-smoking zone", "You're in a known no-smoking place. The app shows the way out and the nearest spot.")
                    legendRow("exclamationmark.triangle.fill", .orange, "Edge of a zone", "A no-smoking zone starts within your GPS margin of error.")
                    legendRow("checkmark.circle.fill", .green, "Smoking area", "You're at an NEA yellow box or a reported smoking corner.")
                    legendRow("checkmark.circle", .teal, "Zone OK", "No known restriction here. Outdoors, not under a shelter, away from entrances: generally allowed.")
                }

                Section {
                    reliabilityRow(.official, "NEA: the yellow boxes of Orchard Road, the Orchard no-smoking zone, hawker centres.")
                    reliabilityRow(.official, "NParks: smoke-free parks and gardens.")
                    reliabilityRow(.official, "Changi Airport Group: the airport's smoking areas. Described in words, so pinned at the gate they mention or at the terminal: approximate position.")
                    reliabilityRow(.official, "HSA: the register of licensed retailers. Located to the building of the postal code.")
                    reliabilityRow(.indicative, "OpenStreetMap: smoking corners, bus stops, playgrounds, courts, schools, hospitals… Thorough in places, patchy in others.")
                } header: {
                    Text("How reliable each source is")
                } footer: {
                    Text("On the map, official zones have a solid outline, OpenStreetMap ones a dashed outline.")
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
                    Text("Where smoking is banned in Singapore")
                } footer: {
                    Text("\(Legal.fine) \(Legal.vape)")
                }

                Section("Data") {
                    if let meta = model.data?.meta {
                        LabeledContent("Generated on", value: Format.date(meta.generated) ?? meta.generated)
                        ForEach(meta.sources) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name).font(.subheadline.weight(.semibold))
                                Text([source.publisher, Format.date(source.updated).map { "updated \($0)" }, source.licence]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let data = model.data {
                        LabeledContent("Smoking spots", value: "\(data.spots.count)")
                        LabeledContent("No-smoking places", value: "\(data.zones.count)")
                        LabeledContent("Licensed retailers", value: "\(data.retailers.count)")
                    }
                }

                Section("Privacy") {
                    Label("Your location is only used while the app is open, on your phone.", systemImage: "location")
                    Label("No account, no tracking, no analytics: nothing is sent to SingaSmoke.", systemImage: "hand.raised")
                    Label("The network is used for Apple's map and routes, and for NEA photos. The verdict and the lists work offline.", systemImage: "wifi")
                }

                Section {
                    Text("Contains information from the Designated Smoking Areas, No-Smoking Zones, Hawker Centres, NParks No-Smoking Locations and Listing of Licensed Tobacco Retailers datasets accessed from data.gov.sg, made available under the terms of the Singapore Open Data Licence version 1.0.")
                    Text("© OpenStreetMap contributors, data under the ODbL.")
                    Text("Geocoding: OneMap © Singapore Land Authority. Changi smoking areas: Changi Airport Group.")
                    Text("Unofficial app, not affiliated with NEA, NParks, HSA, SLA or Changi Airport Group. Data processing inspired by smokingarea-sg (MIT).")
                    Link("Source code on GitHub", destination: URL(string: "https://github.com/TheNarciss/SingaSmoke")!)
                } header: {
                    Text("Licences and attributions")
                }
                .font(.footnote)
            }
            .navigationTitle("Info")
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
                    Text("Before you start")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    point("signpost.right.fill", Legal.signage)
                    point("clock.arrow.circlepath", "The data comes from public sources (NEA, NParks, HSA, Changi Airport, OpenStreetMap) and can be out of date or incomplete.")
                    point("eye.slash", Legal.unmapped)
                    point("banknote", Legal.fine)
                    point("nosign", Legal.vape)
                    point("location", "Your location is only used while the app is open. Nothing is collected or sent.")
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onAccept) {
                    Text("Got it")
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
