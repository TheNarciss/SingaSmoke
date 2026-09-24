import SingaSmokeCore
import SwiftUI

/// How to read the app, how far to trust it, where everything comes from.
struct InfoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showDisclaimer = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Logo(size: 84)
                        Text("SingaSmoke")
                            .font(.title.weight(.heavy))
                        Text("Where you can smoke in Singapore, and where you can't.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Label(Legal.signage, systemImage: "signpost.right.fill")
                    Text("The data can be out of date: a spot may be gone, a zone may have changed. SingaSmoke helps you find your way; it doesn't replace the signs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Read the warning again") { showDisclaimer = true }
                } header: {
                    Text("First things first")
                }

                Section("The status card") {
                    legendRow("nosign", Brand.danger, "No smoking here", "You're in a known no-smoking place. The app shows the way out and the nearest spots.")
                    legendRow("exclamationmark", Brand.warning, "Near a no-smoking zone", "A zone starts within your GPS margin of error.")
                    legendRow("checkmark", Brand.allowed, "Smoking area", "You're at an NEA yellow box or a reported smoking corner.")
                    legendRow("hand.thumbsup.fill", Brand.allowed, "No known restriction", "Outdoors, away from shelters and entrances: generally fine.")
                }

                Section {
                    reliabilityRow(.official, "NEA: the yellow boxes of Orchard Road, the Orchard no-smoking zone, hawker centres.")
                    reliabilityRow(.official, "NParks: smoke-free parks and gardens.")
                    reliabilityRow(.official, "Changi Airport Group: the airport's smoking areas. Described in words, so pinned at the gate they mention or at the terminal.")
                    reliabilityRow(.official, "HSA: the register of licensed retailers, located to the building of the postal code.")
                    reliabilityRow(.indicative, "OpenStreetMap: smoking corners, bus stops, playgrounds, courts, schools, hospitals… Thorough in places, patchy in others.")
                } header: {
                    Text("How reliable each source is")
                } footer: {
                    Text("On the map, official zones have a solid outline, OpenStreetMap ones a dashed outline.")
                }

                Section {
                    ForEach(ZoneKind.allCases.filter { $0 != .other }, id: \.self) { kind in
                        HStack(alignment: .top, spacing: 12) {
                            IconCircle(symbol: kind.symbol, tint: Brand.danger, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.label).font(.subheadline.weight(.semibold))
                                Text(kind.rule).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Label(Legal.unmapped, systemImage: "eye.slash")
                        .font(.footnote)
                } header: {
                    Text("Where smoking is banned")
                } footer: {
                    Text("\(Legal.fine) \(Legal.vape)")
                }

                Section("Data") {
                    if let meta = model.data?.meta {
                        LabeledContent("Generated", value: Format.date(meta.generated) ?? meta.generated)
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
                    Label("Your location is only used while the app is open, on your phone.", systemImage: "location.fill")
                    Label("No account, no tracking, no analytics: nothing is sent to SingaSmoke.", systemImage: "hand.raised.fill")
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
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showDisclaimer) {
                DisclaimerSheet(onAccept: { showDisclaimer = false })
            }
        }
    }

    private func legendRow(_ symbol: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconCircle(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func reliabilityRow(_ reliability: Reliability, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ReliabilityChips(reliability: reliability)
            Text(text).font(.footnote)
        }
    }
}

/// The app icon, for in-app headers.
struct Logo: View {
    var size: CGFloat = 72

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            .accessibilityHidden(true)
    }
}

/// Shown at first launch, and on demand from About.
struct DisclaimerSheet: View {
    var onAccept: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Logo(size: 72)
                        .padding(.top, 36)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Before you go")
                            .font(.largeTitle.weight(.heavy))
                            .accessibilityAddTraits(.isHeader)
                        Text("SingaSmoke shows where smoking is allowed and banned in Singapore, from public data.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        point("signpost.right.fill", Color(white: 0.15), Legal.signage)
                        point("clock.arrow.circlepath", Brand.warning, "The data comes from NEA, NParks, HSA, Changi Airport and OpenStreetMap, and can be out of date or incomplete.")
                        point("eye.slash.fill", Brand.danger, Legal.unmapped)
                        point("banknote.fill", Brand.danger, Legal.fine)
                        point("nosign", Brand.danger, Legal.vape)
                        point("location.fill", Brand.allowed, "Your location is only used while the app is open. Nothing is collected or sent.")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            Button("Got it", action: onAccept)
                .buttonStyle(.pill)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconCircle(symbol: symbol, tint: tint, size: 34)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
