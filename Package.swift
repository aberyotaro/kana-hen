// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kanahen",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Conversion"),
        .target(name: "Capture"),
        .executableTarget(name: "kanahen", dependencies: ["Conversion", "Capture"]),
        // Command Line Tools だけでは XCTest / swift-testing が使えないため、実行形式のテストにしている
        .executableTarget(name: "selftest", dependencies: ["Conversion", "Capture"], path: "Tests/SelfTest"),
    ]
)
