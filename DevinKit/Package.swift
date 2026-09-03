// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevinKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DevinKit", targets: ["DevinKit"]),
    ],
    targets: [
        .target(name: "DevinKit"),
        .testTarget(name: "DevinKitTests", dependencies: ["DevinKit"]),
    ]
)
