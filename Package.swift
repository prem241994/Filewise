// swift-tools-version: 6.0
import PackageDescription

// Mirrors scripts/common.sh, which builds the same two modules directly with
// swiftc because Swift Package Manager is unusable on the development Mac.
let package = Package(
    name: "Filewise",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Filewise", targets: ["Filewise"])],
    targets: [
        // Models, SQLite index, scanning, search, and Trash. No UI.
        .target(name: "FilewiseCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        // SwiftUI views and the main-actor view model.
        .executableTarget(name: "Filewise", dependencies: ["FilewiseCore"]),
    ]
)
