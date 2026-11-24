// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Keylume",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KeylumeKit", targets: ["KeylumeKit"]),
        .executable(name: "keylumectl", targets: ["keylumectl"]),
        .executable(name: "Keylume", targets: ["Keylume"]),
    ],
    targets: [
        .target(name: "KeylumeKit"),
        .executableTarget(name: "keylumectl", dependencies: ["KeylumeKit"]),
        .executableTarget(name: "Keylume", dependencies: ["KeylumeKit"]),
        // XCTest / swift-testing need a full Xcode; this self-contained runner works with the Command Line Tools:
        //   swift run keylume-selftest
        .executableTarget(name: "keylume-selftest", dependencies: ["KeylumeKit"], path: "Sources/KeylumeSelfTest"),
    ]
)
