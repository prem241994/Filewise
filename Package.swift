// swift-tools-version: 6.0
import PackageDescription

// Mirrors scripts/common.sh, which builds the same two modules directly with
// swiftc because Swift Package Manager is unusable on the development Mac.
let package = Package(
    name: "Filewise",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Filewise", targets: ["Filewise"])],
    targets: [
        // Models, SQLite index, scanning, search, Trash, and on-device text
        // recognition for screenshots (Vision). No UI.
        .target(name: "FilewiseCore", linkerSettings: [.linkedLibrary("sqlite3"), .linkedFramework("Vision")]),
        // SwiftUI views and the main-actor view model.
        .executableTarget(name: "Filewise", dependencies: ["FilewiseCore"]),
    ]
)
