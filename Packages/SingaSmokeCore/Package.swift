// swift-tools-version: 5.9
// Everything the app decides lives here: geometry, zones, the verdict, formatting.
// Foundation only, so it builds and tests on macOS and Linux alike (`swift test`).
import PackageDescription

let package = Package(
    name: "SingaSmokeCore",
    defaultLocalization: "fr",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SingaSmokeCore", targets: ["SingaSmokeCore"]),
    ],
    targets: [
        .target(name: "SingaSmokeCore"),
        .testTarget(name: "SingaSmokeCoreTests", dependencies: ["SingaSmokeCore"]),
    ]
)
