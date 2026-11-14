// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Filewise",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Filewise", targets: ["Filewise"])],
    targets: [.executableTarget(name: "Filewise")]
)
