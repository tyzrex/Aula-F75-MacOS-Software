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
        // XCTest / swift-testing need a full Xcode; this self-contained runner works with the Command Line Tools:
        //   swift run aula-selftest
        .executableTarget(name: "aula-selftest", dependencies: ["AulaKit"], path: "Sources/AulaSelfTest"),
    ]
)
