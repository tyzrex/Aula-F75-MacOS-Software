// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AulaHub",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AulaKit", targets: ["AulaKit"]),

    ],
    targets: [
        .target(name: "AulaKit"),

    ]
)
